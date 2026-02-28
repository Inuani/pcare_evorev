import Liminal "mo:liminal";
import Principal "mo:core/Principal";
import Error "mo:core/Error";
import Time "mo:core/Time";
import Result "mo:core/Result";
import Iter "mo:core/Iter";
import AssetsMiddleware "mo:liminal/Middleware/Assets";
import HttpAssets "mo:http-assets@0";
import AssetCanister "mo:liminal/AssetCanister";
import Text "mo:core/Text";
import ProtectedRoutes "nfc_protec_routes";
import Routes "routes";
import Scan "scan";
import Nat "mo:core/Nat";
import Array "mo:core/Array";
import JwtMiddleware "mo:liminal/Middleware/JWT";
import JWT "mo:jwt";
import Map "mo:map/Map";
import RouterMiddleware "mo:liminal/Middleware/Router";
import App "mo:liminal/App";
import HttpContext "mo:liminal/HttpContext";
import InvalidScan "invalid_scan";
import Types "models/Types";
import State "models/State";

shared ({ caller = initializer }) persistent actor class Actor() = self {

    transient let canisterId = Principal.fromActor(self);
    var admin_principal : Principal = initializer;

    func isAdmin(caller : Principal) : Bool {
        caller == admin_principal;
    };

    var appState = State.init();
    var user_counter : Nat = 0;

    var assetStableData = HttpAssets.init_stable_store(canisterId, initializer);
    assetStableData := HttpAssets.upgrade_stable_store(assetStableData);

    let protectedRoutesState = ProtectedRoutes.init();
    transient let protected_routes_storage = ProtectedRoutes.RoutesStorage(protectedRoutesState);

    transient let setPermissions : HttpAssets.SetPermissions = {
        commit = [initializer];
        manage_permissions = [initializer];
        prepare = [initializer];
    };
    transient var assetStore = HttpAssets.Assets(assetStableData, ?setPermissions);
    transient var assetCanister = AssetCanister.AssetCanister(assetStore);

    transient let assetMiddlewareConfig : AssetsMiddleware.Config = {
        store = assetStore;
    };

    func createJWTMiddleware() : App.Middleware {
        JwtMiddleware.new({
            validation = {
                expiration = true;
                notBefore = false;
                issuer = #skip;
                audience = #skip;
                signature = #key(#symmetric(appState.jwt_secret));
            };
            locations = [#queryString("token")];
        });
    };

    // --- Admin Endpoints ---

    public shared ({ caller }) func add_user(username : Text, nfc_uid : Text) : async Types.UserId {
        if (not isAdmin(caller)) {
            throw Error.reject("Not authorized: Must be Admin to add users.");
        };

        user_counter += 1;
        let userId = "user_" # Nat.toText(user_counter);

        let newUser : Types.User = {
            id = userId;
            username = username;
            active_nfc_uids = [nfc_uid];
        };

        ignore Map.put(appState.users, Map.thash, userId, newUser);
        ignore Map.put(appState.nfc_mapping, Map.thash, nfc_uid, userId);

        userId;
    };

    public shared query ({ caller }) func get_all_users() : async [Types.User] {
        if (not isAdmin(caller)) {
            throw Error.reject("Not authorized: Must be Admin to list users.");
        };
        Iter.toArray(Map.vals(appState.users));
    };

    public shared ({ caller }) func add_project(id : Text, name : Text, lead_id : Text) : async () {
        if (not isAdmin(caller)) {
            throw Error.reject("Not authorized: Must be Admin to add projects.");
        };

        switch (Map.get(appState.users, Map.thash, lead_id)) {
            case null { throw Error.reject("Lead user does not exist") };
            case (?_) {};
        };

        let newProject : Types.Project = {
            id = id;
            name = name;
            current_supply = 0;
            total_liquid = 0;
            total_staked = 0;
            lead_id = lead_id;
            treasury = [];
        };

        ignore Map.put(appState.projects, Map.thash, id, newProject);
    };

    public shared ({ caller }) func recover_nfc_tag(user_id : Text, new_nfc_uid : Text, old_nfc_uid : ?Text) : async () {
        if (not isAdmin(caller)) {
            throw Error.reject("Not authorized: Must be Admin to recover tags.");
        };

        switch (Map.get(appState.users, Map.thash, user_id)) {
            case null { throw Error.reject("User does not exist") };
            case (?user) {
                switch (old_nfc_uid) {
                    case (?old_uid) {
                        ignore Map.remove(appState.nfc_mapping, Map.thash, old_uid);
                    };
                    case null {};
                };

                ignore Map.put(appState.nfc_mapping, Map.thash, new_nfc_uid, user_id);

                let updatedUser = {
                    user with active_nfc_uids = Array.concat<Text>(user.active_nfc_uids, [new_nfc_uid])
                };
                ignore Map.put(appState.users, Map.thash, user_id, updatedUser);
            };
        };
    };

    // --- Internal Helpers ---

    private func get_balance(holder_id : Text, token_id : Text) : Types.Balance {
        switch (Map.get(appState.ledger, Map.combineHash(Map.thash, Map.thash), (holder_id, token_id))) {
            case null { { liquid = 0; staked = 0 } };
            case (?b) { b };
        };
    };

    private func set_balance(holder_id : Text, token_id : Text, balance : Types.Balance) {
        ignore Map.put(appState.ledger, Map.combineHash(Map.thash, Map.thash), (holder_id, token_id), balance);
    };

    // --- Internal Bypasses for Authenticated SSR Dashboard ---

    private func mint_internal(
        project_id : Types.ProjectId,
        recipient_input : Text,
        amount_liquid : Nat,
        amount_staked : Nat,
        _justification : Text,
    ) : async Result.Result<(), Text> {
        let recipient_id = switch (resolve_user_id(recipient_input)) {
            case (?id) id;
            case null return #err("Recipient username not found.");
        };

        let project = switch (Map.get(appState.projects, Map.thash, project_id)) {
            case null { return #err("Project does not exist") };
            case (?p) { p };
        };

        let total_mint = amount_liquid + amount_staked;
        let updatedProject = {
            project with
            current_supply = project.current_supply + total_mint;
            total_liquid = project.total_liquid + amount_liquid;
            total_staked = project.total_staked + amount_staked;
        };
        ignore Map.put(appState.projects, Map.thash, project_id, updatedProject);

        let newRecord : Types.MintRecord = {
            timestamp = Time.now() / 1_000_000_000;
            amount_liquid = amount_liquid;
            justification = _justification;
        };

        let history = switch (Map.get(appState.mint_history, Map.thash, project_id)) {
            case null [];
            case (?h) h;
        };
        ignore Map.put(appState.mint_history, Map.thash, project_id, Array.concat(history, [newRecord]));

        let bal = get_balance(recipient_id, project_id);
        let new_bal : Types.Balance = {
            liquid = bal.liquid + amount_liquid;
            staked = bal.staked + amount_staked;
        };
        set_balance(recipient_id, project_id, new_bal);
        #ok(());
    };

    private func resolve_user_id(input : Text) : ?Types.UserId {
        // First check if input is exactly a User ID
        switch (Map.get(appState.users, Map.thash, input)) {
            case (?user) return ?user.id;
            case null {};
        };
        // Otherwise, search by exact username match (case-sensitive)
        for (user in Map.vals(appState.users)) {
            if (user.username == input) {
                return ?user.id;
            };
        };
        null;
    };

    private func pay_internal(
        from_id : Types.UserId,
        to_target_input : Text,
        token_project_id : Types.ProjectId,
        amount : Nat,
    ) : async Result.Result<(), Text> {
        let to_target_id = switch (resolve_user_id(to_target_input)) {
            case (?id) id;
            case null return #err("Recipient username not found.");
        };

        if (from_id == to_target_id) {
            return #err("Cannot transfer tokens to yourself.");
        };

        let from_bal = get_balance(from_id, token_project_id);
        if (from_bal.liquid < amount) {
            return #err("Insufficient liquid tokens.");
        };

        let to_bal = get_balance(to_target_id, token_project_id);

        let new_from_bal : Types.Balance = {
            liquid = from_bal.liquid - amount;
            staked = from_bal.staked;
        };

        let new_to_bal : Types.Balance = {
            liquid = to_bal.liquid + amount;
            staked = to_bal.staked;
        };

        set_balance(from_id, token_project_id, new_from_bal);
        set_balance(to_target_id, token_project_id, new_to_bal);
        #ok(());
    };

    private func stake_internal(
        holder_id : Types.UserId,
        token_project_id : Types.ProjectId,
        amount : Nat,
    ) : async Result.Result<(), Text> {
        let bal = get_balance(holder_id, token_project_id);
        if (bal.liquid < amount) {
            return #err("Insufficient liquid tokens to stake.");
        };

        let new_bal : Types.Balance = {
            liquid = bal.liquid - amount;
            staked = bal.staked + amount;
        };

        // Also move global liquidity tracking to staked side
        switch (Map.get(appState.projects, Map.thash, token_project_id)) {
            case null {};
            case (?p) {
                let updatedP = {
                    p with
                    total_liquid = p.total_liquid - amount;
                    total_staked = p.total_staked + amount;
                };
                ignore Map.put(appState.projects, Map.thash, token_project_id, updatedP);
            };
        };

        set_balance(holder_id, token_project_id, new_bal);
        #ok(());
    };

    private func get_user_internal(user_id : Types.UserId) : ?Types.User {
        Map.get(appState.users, Map.thash, user_id);
    };

    private func get_all_projects_internal() : [Types.Project] {
        Iter.toArray(Map.vals(appState.projects));
    };

    private func get_all_balances_internal(user_id : Types.UserId) : [(Types.ProjectId, Types.Balance)] {
        var bals : [(Types.ProjectId, Types.Balance)] = [];
        for (proj in get_all_projects_internal().vals()) {
            let b = get_balance(user_id, proj.id);
            if (b.liquid > 0 or b.staked > 0) {
                bals := Array.concat(bals, [(proj.id, b)]);
            };
        };
        bals;
    };

    private func get_mint_history_internal(project_id : Types.ProjectId) : [Types.MintRecord] {
        switch (Map.get(appState.mint_history, Map.thash, project_id)) {
            case null [];
            case (?h) h;
        };
    };

    // --- Http server methods ---
    transient let app = Liminal.App({
        middleware = [
            createJWTMiddleware(),
            AssetsMiddleware.new(assetMiddlewareConfig),
            RouterMiddleware.new(
                Routes.routerConfig(
                    Principal.toText(canisterId),
                    {
                        mint = mint_internal;
                        pay = pay_internal;
                        stake = stake_internal;
                        getUser = get_user_internal;
                        getProjects = get_all_projects_internal;
                        getBalances = get_all_balances_internal;
                        getMintHistory = get_mint_history_internal;
                        getJwtSecret = func() { appState.jwt_secret };
                        getUidMapping = func(uid) {
                            Map.get(appState.nfc_mapping, Map.thash, uid);
                        };
                        verifyNfc = func(url) {
                            protected_routes_storage.verifyRouteAccess("pcare/login", url);
                        };
                    },
                )
            ),
        ];
        errorSerializer = Liminal.defaultJsonErrorSerializer;
        candidRepresentationNegotiator = Liminal.defaultCandidRepresentationNegotiator;
        logger = Liminal.buildDebugLogger(#info);
        urlNormalization = {
            usernameIsCaseSensitive = false;
            pathIsCaseSensitive = true;
            queryKeysAreCaseSensitive = false;
            removeEmptyPathSegments = true;
            resolvePathDotSegments = true;
            preserveTrailingSlash = false;
        };
    });

    public query func http_request(request : Liminal.RawQueryHttpRequest) : async Liminal.RawQueryHttpResponse {
        app.http_request(request);
    };

    public func http_request_update(request : Liminal.RawUpdateHttpRequest) : async Liminal.RawUpdateHttpResponse {
        var mutableRequest = request;

        switch (Scan.getUid(request.url)) {
            case (?uid) {
                switch (Map.get(appState.nfc_mapping, Map.thash, uid)) {
                    case (?userId) {
                        mutableRequest := {
                            mutableRequest with url = request.url # "&userId=" # userId
                        };
                    };
                    case null {};
                };
            };
            case null {};
        };

        await* app.http_request_update(mutableRequest);
    };

    public query func http_request_streaming_callback(token : HttpAssets.StreamingToken) : async HttpAssets.StreamingCallbackResponse {
        switch (assetStore.http_request_streaming_callback(token)) {
            case (#err(e)) throw Error.reject(e);
            case (#ok(response)) response;
        };
    };

    assetStore.set_streaming_callback(http_request_streaming_callback);

    // public shared query func api_version() : async Nat16 {
    //     assetCanister.api_version();
    // };

    // public shared query func get(args : HttpAssets.GetArgs) : async HttpAssets.EncodedAsset {
    //     assetCanister.get(args);
    // };

    // public shared query func get_chunk(args : HttpAssets.GetChunkArgs) : async (HttpAssets.ChunkContent) {
    //     assetCanister.get_chunk(args);
    // };

    // public shared ({ caller }) func grant_permission(args : HttpAssets.GrantPermission) : async () {
    //     await* assetCanister.grant_permission(caller, args);
    // };

    // public shared ({ caller }) func revoke_permission(args : HttpAssets.RevokePermission) : async () {
    //     await* assetCanister.revoke_permission(caller, args);
    // };

    public shared query func list(args : {}) : async [HttpAssets.AssetDetails] {
        assetCanister.list(args);
    };

    // public shared ({ caller }) func store(args : HttpAssets.StoreArgs) : async () {
    //     assetCanister.store(caller, args);
    // };

    // public shared ({ caller }) func create_asset(args : HttpAssets.CreateAssetArguments) : async () {
    //     assetCanister.create_asset(caller, args);
    // };

    // public shared ({ caller }) func set_asset_content(args : HttpAssets.SetAssetContentArguments) : async () {
    //     await* assetCanister.set_asset_content(caller, args);
    // };

    // public shared ({ caller }) func unset_asset_content(args : HttpAssets.UnsetAssetContentArguments) : async () {
    //     assetCanister.unset_asset_content(caller, args);
    // };

    public shared ({ caller }) func delete_asset(args : HttpAssets.DeleteAssetArguments) : async () {
        assetCanister.delete_asset(caller, args);
    };

    // public shared ({ caller }) func set_asset_properties(args : HttpAssets.SetAssetPropertiesArguments) : async () {
    //     assetCanister.set_asset_properties(caller, args);
    // };

    // public shared ({ caller }) func clear(args : HttpAssets.ClearArguments) : async () {
    //     assetCanister.clear(caller, args);
    // };

    public shared ({ caller }) func create_batch(args : {}) : async (HttpAssets.CreateBatchResponse) {
        assetCanister.create_batch(caller, args);
    };

    public shared ({ caller }) func create_chunk(args : HttpAssets.CreateChunkArguments) : async (HttpAssets.CreateChunkResponse) {
        assetCanister.create_chunk(caller, args);
    };

    public shared ({ caller }) func create_chunks(args : HttpAssets.CreateChunksArguments) : async HttpAssets.CreateChunksResponse {
        await* assetCanister.create_chunks(caller, args);
    };

    public shared ({ caller }) func commit_batch(args : HttpAssets.CommitBatchArguments) : async () {
        await* assetCanister.commit_batch(caller, args);
    };

    // public shared ({ caller }) func propose_commit_batch(args : HttpAssets.CommitBatchArguments) : async () {
    //     assetCanister.propose_commit_batch(caller, args);
    // };

    // public shared ({ caller }) func commit_proposed_batch(args : HttpAssets.CommitProposedBatchArguments) : async () {
    //     await* assetCanister.commit_proposed_batch(caller, args);
    // };

    // public shared ({ caller }) func compute_evidence(args : HttpAssets.ComputeEvidenceArguments) : async (?Blob) {
    //     await* assetCanister.compute_evidence(caller, args);
    // };

    // public shared ({ caller }) func delete_batch(args : HttpAssets.DeleteBatchArguments) : async () {
    //     assetCanister.delete_batch(caller, args);
    // };

    // public shared func list_permitted(args : HttpAssets.ListPermitted) : async ([Principal]) {
    //     assetCanister.list_permitted(args);
    // };

    // public shared ({ caller }) func take_ownership() : async () {
    //     await* assetCanister.take_ownership(caller);
    // };

    // public shared ({ caller }) func get_configuration() : async (HttpAssets.ConfigurationResponse) {
    //     assetCanister.get_configuration(caller);
    // };

    // public shared ({ caller }) func configure(args : HttpAssets.ConfigureArguments) : async () {
    //     assetCanister.configure(caller, args);
    // };

    // public shared func certified_tree(args : {}) : async (HttpAssets.CertifiedTree) {
    //     assetCanister.certified_tree(args);
    // };
    // public shared func validate_grant_permission(args : HttpAssets.GrantPermission) : async (Result.Result<Text, Text>) {
    //     assetCanister.validate_grant_permission(args);
    // };

    // public shared func validate_revoke_permission(args : HttpAssets.RevokePermission) : async (Result.Result<Text, Text>) {
    //     assetCanister.validate_revoke_permission(args);
    // };

    // public shared func validate_take_ownership() : async (Result.Result<Text, Text>) {
    //     assetCanister.validate_take_ownership();
    // };

    // public shared func validate_commit_proposed_batch(args : HttpAssets.CommitProposedBatchArguments) : async (Result.Result<Text, Text>) {
    //     assetCanister.validate_commit_proposed_batch(args);
    // };

    // public shared func validate_configure(args : HttpAssets.ConfigureArguments) : async (Result.Result<Text, Text>) {
    //     assetCanister.validate_configure(args);
    // };

    public shared ({ caller }) func add_protected_route(path : Text) : async () {
        assert (caller == initializer);
        ignore protected_routes_storage.addProtectedRoute(path);
    };

    public shared ({ caller }) func update_route_cmacs(path : Text, uid : Text, new_cmacs : [Text]) : async () {
        assert (caller == initializer);
        ignore protected_routes_storage.updateRouteCmacs(path, uid, new_cmacs);
    };

    public shared ({ caller }) func append_route_cmacs(path : Text, uid : Text, new_cmacs : [Text]) : async () {
        assert (caller == initializer);
        ignore protected_routes_storage.appendRouteCmacs(path, uid, new_cmacs);
    };

    public query func get_route_protection(path : Text) : async ?ProtectedRoutes.ProtectedRoute {
        protected_routes_storage.getRoute(path);
    };

    public query func get_route_cmacs(path : Text, uid : Text) : async [Text] {
        protected_routes_storage.getRouteCmacs(path, uid);
    };

    public query func listProtectedRoutesSummary() : async [(Text, Nat)] {
        protected_routes_storage.listProtectedRoutesSummary();
    };

};
