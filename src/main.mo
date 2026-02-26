import Liminal "mo:liminal";
import Principal "mo:core/Principal";
import Error "mo:core/Error";
import AssetsMiddleware "mo:liminal/Middleware/Assets";
import HttpAssets "mo:http-assets@0";
import AssetCanister "mo:liminal/AssetCanister";
import Text "mo:core/Text";
import ProtectedRoutes "nfc_protec_routes";
import Routes "routes";
import Scan "scan";
import Nat "mo:core/Nat";
import Array "mo:core/Array";
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

    func createNFCProtectionMiddleware() : App.Middleware {
        {
            name = "NFC Protection";
            handleQuery = func(context : HttpContext.HttpContext, next : App.Next) : App.QueryResult {
                if (protected_routes_storage.isProtectedRoute(context.request.url)) {
                    return #upgrade; // Force verification in update call
                };
                next();
            };
            handleUpdate = func(context : HttpContext.HttpContext, next : App.NextAsync) : async* App.HttpResponse {
                let url = context.request.url;
                if (protected_routes_storage.isProtectedRoute(url)) {
                    let routes_array = protected_routes_storage.listProtectedRoutes();
                    for ((path, protection) in routes_array.vals()) {
                        if (Text.contains(url, #text path)) {
                            if (not protected_routes_storage.verifyRouteAccess(path, url)) {
                                return {
                                    statusCode = 403;
                                    headers = [("Content-Type", "text/html")];
                                    body = ?Text.encodeUtf8(InvalidScan.generateInvalidScanPage());
                                    streamingStrategy = null;
                                };
                            };
                        };
                    };
                };
                await* next();
            };
        };
    };

    transient let app = Liminal.App({
        middleware = [
            createNFCProtectionMiddleware(),
            AssetsMiddleware.new(assetMiddlewareConfig),
            RouterMiddleware.new(
                Routes.routerConfig(
                    Principal.toText(canisterId)
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

    // --- Core Economic Endpoints ---

    public shared ({ caller }) func mint(
        project_id : Types.ProjectId,
        recipient_id : Types.UserId,
        amount_liquid : Nat,
        amount_staked : Nat,
        _justification : Text,
    ) : async () {
        if (not isAdmin(caller)) {
            // In a fully decentralized setup, we might also verify if the caller is the lead_id
            // For now, only the trusted admin (e.g. Discord Bot) can trigger mints based on consensus.
            throw Error.reject("Not authorized: Must be Admin to mint.");
        };

        // Update Project Supply
        let project = switch (Map.get(appState.projects, Map.thash, project_id)) {
            case null { throw Error.reject("Project does not exist") };
            case (?p) { p };
        };

        let total_mint = amount_liquid + amount_staked;
        let updatedProject = {
            project with current_supply = project.current_supply + total_mint
        };
        ignore Map.put(appState.projects, Map.thash, project_id, updatedProject);

        // Update Recipient Ledger
        let bal = get_balance(recipient_id, project_id);
        let new_bal : Types.Balance = {
            liquid = bal.liquid + amount_liquid;
            staked = bal.staked + amount_staked;
        };
        set_balance(recipient_id, project_id, new_bal);
    };

    public shared ({ caller }) func pay(
        from_id : Types.UserId,
        to_target_id : Text, // Can be a UserId or a ProjectId
        token_project_id : Types.ProjectId,
        amount : Nat,
    ) : async () {
        if (not isAdmin(caller)) {
            throw Error.reject("Not authorized: Must be Admin to execute payments.");
        };

        let from_bal = get_balance(from_id, token_project_id);
        if (from_bal.liquid < amount) {
            throw Error.reject("Insufficient liquid tokens.");
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
    };

    public shared ({ caller }) func stake(
        holder_id : Types.UserId,
        token_project_id : Types.ProjectId,
        amount : Nat,
    ) : async () {
        if (not isAdmin(caller)) {
            throw Error.reject("Not authorized: Must be Admin to execute stakes.");
        };

        let bal = get_balance(holder_id, token_project_id);
        if (bal.liquid < amount) {
            throw Error.reject("Insufficient liquid tokens to stake.");
        };

        let new_bal : Types.Balance = {
            liquid = bal.liquid - amount;
            staked = bal.staked + amount;
        };

        set_balance(holder_id, token_project_id, new_bal);
    };

    // --- Http server methods ---

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
