import Router "mo:liminal/Router";
import RouteContext "mo:liminal/RouteContext";
import Liminal "mo:liminal";
import Result "mo:core/Result";
import Text "mo:core/Text";
import Iter "mo:core/Iter";
import Option "mo:core/Option";
import Array "mo:core/Array";
import Nat "mo:core/Nat";
import Types "models/Types";
import JWT "mo:jwt";
import Time "mo:core/Time";
import Blob "mo:core/Blob";
import Scan "scan";
import Float "mo:core/Float";
import UI "ui";
import HMAC "mo:hmac";
import Debug "mo:core/Debug";

module Routes {

    public type BackendCtx = {
        mint : (Types.ProjectId, Text, Nat, Nat, Text) -> async Result.Result<(), Text>;
        pay : (Types.UserId, Text, Types.ProjectId, Nat) -> async Result.Result<(), Text>;
        stake : (Types.UserId, Types.ProjectId, Nat) -> async Result.Result<(), Text>;
        getUser : (Types.UserId) -> ?Types.User;
        getProjects : () -> [Types.Project];
        getBalances : (Types.UserId) -> [(Types.ProjectId, Types.Balance)];
        getMintHistory : (Types.ProjectId) -> [Types.MintRecord];
        getJwtSecret : () -> Blob;
        getUidMapping : (Text) -> ?Types.UserId;
        verifyNfc : (Text) -> Bool;
    };

    private func getAuthenticatedUserId(ctx : RouteContext.RouteContext) : ?Text {
        return ?"user_1";

        /*
        switch (ctx.getIdentity()) {
            case null null;
            case (?identity) {
                if (identity.isAuthenticated()) {
                    identity.getId();
                } else {
                    null;
                };
            };
        };
        */
    };

    private func getToken(ctx : RouteContext.RouteContext) : Text {
        switch (ctx.getQueryParam("token")) {
            case (?t) t;
            case null "";
        };
    };

    private func decodeForm(body : Text) : [(Text, Text)] {
        var params : [(Text, Text)] = [];
        let pairs = Text.split(body, #text("&"));
        for (pair in pairs) {
            let kvArray = Iter.toArray(Text.split(pair, #text("=")));
            if (kvArray.size() >= 2) {
                // VERY basic URL decoding replacement for %2B, %20 etc is skipped for brevity but would exist in a prod environment
                params := Array.concat(params, [(kvArray[0], kvArray[1])]);
            };
        };
        params;
    };

    private func getFormValue(form : [(Text, Text)], key : Text) : ?Text {
        for ((k, v) in form.vals()) {
            if (k == key) { return ?v };
        };
        null;
    };

    public func routerConfig(_canisterId : Text, bCtx : BackendCtx) : Router.Config {
        {
            prefix = null;
            identityRequirement = null;
            routes = [
                Router.get(
                    "/pcare/login",
                    #update(
                        #async_(
                            func(ctx : RouteContext.RouteContext) : async* Liminal.HttpResponse {
                                let uidOpt = ctx.getQueryParam("uid");
                                let _ctrOpt = ctx.getQueryParam("ctr");
                                let _cmacOpt = ctx.getQueryParam("cmac");

                                // 1. Extract and map UID to UserID
                                let userId = switch (uidOpt) {
                                    case null return ctx.buildResponse(#unauthorized, #html(UI.renderError("Missing UID")));
                                    case (?uid) {
                                        switch (bCtx.getUidMapping(uid)) {
                                            case null return ctx.buildResponse(#unauthorized, #html(UI.renderError("Unregistered NFC Tag")));
                                            case (?id) id;
                                        };
                                    };
                                };

                                // 2. Validate cryptographic scan
                                Debug.print("Login requested. Extracting NFC data from: " # ctx.httpContext.request.url);
                                if (not bCtx.verifyNfc(ctx.httpContext.request.url)) {
                                    return ctx.buildResponse(#unauthorized, #html(UI.renderError("Invalid NFC Tap Signature.")));
                                };

                                // 3. Build JWT
                                let nowSeconds = Float.fromInt(Time.now() / 1_000_000_000);
                                let expSeconds = nowSeconds + 3600.0; // 1 hour session

                                let unsignedToken : JWT.UnsignedToken = {
                                    header = [
                                        ("alg", #string("HS256")),
                                        ("typ", #string("JWT")),
                                    ];
                                    payload = [
                                        ("sub", #string(userId)),
                                        ("iat", #number(#int(Time.now() / 1_000_000_000))),
                                        ("exp", #number(#float(expSeconds))),
                                    ];
                                };

                                let unsignedBlob = JWT.toBlobUnsigned(unsignedToken);

                                let secretArray = Blob.toArray(bCtx.getJwtSecret());
                                let unsignedArray = Blob.toArray(unsignedBlob);
                                let signatureBytes = HMAC.generate(secretArray, unsignedArray.vals(), #sha256);

                                let signedToken : JWT.Token = {
                                    header = unsignedToken.header;
                                    payload = unsignedToken.payload;
                                    signature = {
                                        algorithm = "HS256";
                                        value = signatureBytes;
                                        message = unsignedBlob;
                                    };
                                };

                                let jwtText = JWT.toText(signedToken);

                                ctx.buildResponse(#found, #custom({ headers = [("Location", "/pcare?token=" # jwtText)]; body = Text.encodeUtf8("Redirecting...") }));
                            }
                        )
                    ),
                ),
                Router.get(
                    "/pcare",
                    #update(
                        #async_(
                            func(ctx : RouteContext.RouteContext) : async* Liminal.HttpResponse {
                                let userIdOpt = getAuthenticatedUserId(ctx);
                                switch (userIdOpt) {
                                    case null {
                                        ctx.buildResponse(#unauthorized, #html(UI.renderError("Missing or invalid NFC Tag.")));
                                    };
                                    case (?userId) {
                                        switch (bCtx.getUser(userId)) {
                                            case null {
                                                ctx.buildResponse(#unauthorized, #html(UI.renderError("User profile not found.")));
                                            };
                                            case (?user) {
                                                let balances = bCtx.getBalances(userId);
                                                let projects = bCtx.getProjects();
                                                ctx.buildResponse(#ok, #html(UI.renderDashboard(user, balances, projects, getToken(ctx))));
                                            };
                                        };
                                    };
                                };
                            }
                        )
                    ),
                ),
                Router.post(
                    "/pcare/mint",
                    #update(
                        #async_(
                            func(ctx : RouteContext.RouteContext) : async* Liminal.HttpResponse {
                                let ?bodyText = ctx.parseUtf8Body() else return ctx.buildResponse(#badRequest, #html(UI.renderError("Missing request body.")));
                                let form = decodeForm(bodyText);
                                let userIdOpt = getAuthenticatedUserId(ctx);

                                switch (userIdOpt) {
                                    case null {
                                        ctx.buildResponse(#unauthorized, #html(UI.renderError("Unauthorized.")));
                                    };
                                    case (?userId) {
                                        let projId = getFormValue(form, "projectId");
                                        let recIdRaw = getFormValue(form, "recipientId");
                                        let liq = getFormValue(form, "liquid");
                                        let justRaw = getFormValue(form, "justification");

                                        if (Option.isNull(projId) or Option.isNull(liq)) {
                                            return ctx.buildResponse(#badRequest, #html(UI.renderError("Missing form fields.")));
                                        };

                                        let recipient = switch (recIdRaw) {
                                            case (?r) {
                                                if (r == "") userId else r;
                                            };
                                            case null { userId };
                                        };
                                        let liquidNat = switch (Nat.fromText(Option.unwrap(liq))) {
                                            case (?n) n;
                                            case null 0;
                                        };
                                        let pId = Option.unwrap(projId);
                                        let justification = switch (justRaw) {
                                            case (?j) {
                                                if (j == "") "Dashboard Mint" else j;
                                            };
                                            case null "Dashboard Mint";
                                        };

                                        let result = await bCtx.mint(pId, recipient, liquidNat, 0, justification);

                                        switch (result) {
                                            case (#ok(())) {
                                                ctx.buildResponse(#ok, #html(UI.renderSuccess("Successfully minted tokens.", getToken(ctx))));
                                            };
                                            case (#err(msg)) {
                                                ctx.buildResponse(#badRequest, #html(UI.renderError(msg)));
                                            };
                                        };
                                    };
                                };
                            }
                        )
                    ),
                ),
                Router.post(
                    "/pcare/pay",
                    #update(
                        #async_(
                            func(ctx : RouteContext.RouteContext) : async* Liminal.HttpResponse {
                                let ?bodyText = ctx.parseUtf8Body() else return ctx.buildResponse(#badRequest, #html(UI.renderError("Missing request body.")));
                                let form = decodeForm(bodyText);
                                let userIdOpt = getAuthenticatedUserId(ctx);

                                switch (userIdOpt) {
                                    case null {
                                        ctx.buildResponse(#unauthorized, #html(UI.renderError("Unauthorized.")));
                                    };
                                    case (?userId) {
                                        let projId = switch (getFormValue(form, "projectId")) {
                                            case (?p) p;
                                            case null "";
                                        };
                                        let recId = switch (getFormValue(form, "recipientId")) {
                                            case (?p) p;
                                            case null "";
                                        };
                                        let amount = switch (getFormValue(form, "amount")) {
                                            case (?a) {
                                                switch (Nat.fromText(a)) {
                                                    case (?n) n;
                                                    case null 0;
                                                };
                                            };
                                            case null 0;
                                        };

                                        let result = await bCtx.pay(userId, recId, projId, amount);
                                        switch (result) {
                                            case (#ok(())) {
                                                ctx.buildResponse(#ok, #html(UI.renderSuccess("Transfer successful.", getToken(ctx))));
                                            };
                                            case (#err(msg)) {
                                                ctx.buildResponse(#badRequest, #html(UI.renderError(msg)));
                                            };
                                        };
                                    };
                                };
                            }
                        )
                    ),
                ),
                Router.post(
                    "/pcare/stake",
                    #update(
                        #async_(
                            func(ctx : RouteContext.RouteContext) : async* Liminal.HttpResponse {
                                let ?bodyText = ctx.parseUtf8Body() else return ctx.buildResponse(#badRequest, #html(UI.renderError("Missing request body.")));
                                let form = decodeForm(bodyText);
                                let userIdOpt = getAuthenticatedUserId(ctx);

                                switch (userIdOpt) {
                                    case null {
                                        ctx.buildResponse(#unauthorized, #html(UI.renderError("Unauthorized.")));
                                    };
                                    case (?userId) {
                                        let projId = switch (getFormValue(form, "projectId")) {
                                            case (?p) p;
                                            case null "";
                                        };
                                        let amount = switch (getFormValue(form, "amount")) {
                                            case (?a) {
                                                switch (Nat.fromText(a)) {
                                                    case (?n) n;
                                                    case null 0;
                                                };
                                            };
                                            case null 0;
                                        };

                                        let result = await bCtx.stake(userId, projId, amount);
                                        switch (result) {
                                            case (#ok(())) {
                                                ctx.buildResponse(#ok, #html(UI.renderSuccess("Successfully staked tokens.", getToken(ctx))));
                                            };
                                            case (#err(msg)) {
                                                ctx.buildResponse(#badRequest, #html(UI.renderError(msg)));
                                            };
                                        };
                                    };
                                };
                            }
                        )
                    ),
                ),
                Router.get(
                    "/",
                    #query_(
                        func(ctx : RouteContext.RouteContext) : Liminal.HttpResponse {
                            let projects = bCtx.getProjects();
                            ctx.buildResponse(#ok, #html(UI.renderHomepage(projects)));
                        }
                    ),
                ),
                Router.get(
                    "/registry",
                    #query_(
                        func(ctx : RouteContext.RouteContext) : Liminal.HttpResponse {
                            let url = ctx.httpContext.request.url;

                            var targetedProjectId : ?Text = null;
                            let prefix = "/registry?project=";

                            if (Text.startsWith(url, #text(prefix))) {
                                let parts = Text.split(url, #text(prefix));
                                var finalParts : [Text] = [];
                                for (p in parts) {
                                    finalParts := Array.concat<Text>(finalParts, [p]);
                                };
                                if (finalParts.size() == 2) {
                                    targetedProjectId := ?finalParts[1];
                                };
                            };

                            switch (targetedProjectId) {
                                case null {
                                    // Render main directory
                                    let projects = bCtx.getProjects();
                                    ctx.buildResponse(#ok, #html(UI.renderPublicRegistry(projects)));
                                };
                                case (?pid) {
                                    // Locate the specific project to render the ledger
                                    let projects = bCtx.getProjects();
                                    var foundProject : ?Types.Project = null;
                                    for (p in projects.vals()) {
                                        if (p.id == pid) {
                                            foundProject := ?p;
                                        };
                                    };

                                    switch (foundProject) {
                                        case null {
                                            ctx.buildResponse(#notFound, #html(UI.renderError("Project not found in the registry.")));
                                        };
                                        case (?p) {
                                            let history = bCtx.getMintHistory(p.id);
                                            ctx.buildResponse(#ok, #html(UI.renderProjectLedger(p, history)));
                                        };
                                    };
                                };
                            };
                        }
                    ),
                ),
                Router.get(
                    "/{path}",
                    #query_(
                        func(_ctx) : Liminal.HttpResponse {
                            _ctx.buildResponse(#notFound, #error(#message("Not found")));
                        }
                    ),
                ),
            ];
        };
    };
};
