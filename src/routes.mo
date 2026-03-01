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
        // return ?"user_1";

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

    };

    private func getToken(ctx : RouteContext.RouteContext) : Text {
        switch (ctx.getQueryParam("token")) {
            case (?t) t;
            case null "";
        };
    };

    private func decodeUrlEncoded(str : Text) : Text {
        var s = str;
        let replaces = [
            ("+", " "),
            ("%20", " "),
            ("%21", "!"),
            ("%22", "\""),
            ("%27", "'"),
            ("%28", "("),
            ("%29", ")"),
            ("%2C", ","),
            ("%3A", ":"),
            ("%E2%80%99", "'"),
            ("%C3%80", "À"),
            ("%C3%81", "Á"),
            ("%C3%82", "Â"),
            ("%C3%83", "Ã"),
            ("%C3%84", "Ä"),
            ("%C3%85", "Å"),
            ("%C3%86", "Æ"),
            ("%C3%87", "Ç"),
            ("%C3%88", "È"),
            ("%C3%89", "É"),
            ("%C3%8A", "Ê"),
            ("%C3%8B", "Ë"),
            ("%C3%8C", "Ì"),
            ("%C3%8D", "Í"),
            ("%C3%8E", "Î"),
            ("%C3%8F", "Ï"),
            ("%C3%91", "Ñ"),
            ("%C3%92", "Ò"),
            ("%C3%93", "Ó"),
            ("%C3%94", "Ô"),
            ("%C3%95", "Õ"),
            ("%C3%96", "Ö"),
            ("%C3%99", "Ù"),
            ("%C3%9A", "Ú"),
            ("%C3%9B", "Û"),
            ("%C3%9C", "Ü"),
            ("%C3%A0", "à"),
            ("%C3%A1", "á"),
            ("%C3%A2", "â"),
            ("%C3%A3", "ã"),
            ("%C3%A4", "ä"),
            ("%C3%A5", "å"),
            ("%C3%A6", "æ"),
            ("%C3%A7", "ç"),
            ("%C3%A8", "è"),
            ("%C3%A9", "é"),
            ("%C3%AA", "ê"),
            ("%C3%AB", "ë"),
            ("%C3%AC", "ì"),
            ("%C3%AD", "í"),
            ("%C3%AE", "î"),
            ("%C3%AF", "ï"),
            ("%C3%B1", "ñ"),
            ("%C3%B2", "ò"),
            ("%C3%B3", "ó"),
            ("%C3%B4", "ô"),
            ("%C3%B5", "õ"),
            ("%C3%B6", "ö"),
            ("%C3%B9", "ù"),
            ("%C3%BA", "ú"),
            ("%C3%BB", "û"),
            ("%C3%BC", "ü"),
            ("%E9", "é"),
            ("%E8", "è"),
            ("%E0", "à"),
            ("%E7", "ç"),
            ("%EA", "ê"),
        ];

        for ((enc, dec) in replaces.vals()) {
            var result = "";
            let parts = Text.split(s, #text(enc));
            var first = true;
            for (p in parts) {
                if (first) {
                    result := result # p;
                    first := false;
                } else {
                    result := result # dec # p;
                };
            };
            s := result;
        };
        s;
    };

    private func decodeForm(body : Text) : [(Text, Text)] {
        var params : [(Text, Text)] = [];
        let pairs = Text.split(body, #text("&"));
        for (pair in pairs) {
            let kvArray = Iter.toArray(Text.split(pair, #text("=")));
            if (kvArray.size() >= 2) {
                params := Array.concat(params, [(kvArray[0], decodeUrlEncoded(kvArray[1]))]);
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
                                    case null return ctx.buildResponse(#unauthorized, #html(UI.renderError("UID manquant")));
                                    case (?uid) {
                                        switch (bCtx.getUidMapping(uid)) {
                                            case null return ctx.buildResponse(#unauthorized, #html(UI.renderError("Tag NFC non enregistré")));
                                            case (?id) id;
                                        };
                                    };
                                };

                                // 2. Validate cryptographic scan
                                Debug.print("Login requested. Extracting NFC data from: " # ctx.httpContext.request.url);
                                if (not bCtx.verifyNfc(ctx.httpContext.request.url)) {
                                    return ctx.buildResponse(#unauthorized, #html(UI.renderError("Signature de scan NFC invalide.")));
                                };

                                // 3. Build JWT
                                let nowSeconds = Float.fromInt(Time.now() / 1_000_000_000);
                                let expSeconds = nowSeconds + 1200.0; // 20 minute session

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
                                        ctx.buildResponse(#unauthorized, #html(UI.renderError("Tag NFC manquant ou invalide.")));
                                    };
                                    case (?userId) {
                                        switch (bCtx.getUser(userId)) {
                                            case null {
                                                ctx.buildResponse(#unauthorized, #html(UI.renderError("Profil utilisateur introuvable.")));
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
                                let ?bodyText = ctx.parseUtf8Body() else return ctx.buildResponse(#badRequest, #html(UI.renderError("Corps de requête manquant.")));
                                let form = decodeForm(bodyText);
                                let userIdOpt = getAuthenticatedUserId(ctx);

                                switch (userIdOpt) {
                                    case null {
                                        ctx.buildResponse(#unauthorized, #html(UI.renderError("Non autorisé.")));
                                    };
                                    case (?userId) {
                                        let projId = getFormValue(form, "projectId");
                                        let recIdRaw = getFormValue(form, "recipientId");
                                        let liq = getFormValue(form, "liquid");
                                        let justRaw = getFormValue(form, "justification");

                                        if (Option.isNull(projId) or Option.isNull(liq)) {
                                            return ctx.buildResponse(#badRequest, #html(UI.renderError("Champs de formulaire manquants.")));
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
                                                if (j == "") "Émission via Interface" else j;
                                            };
                                            case null "Émission via Interface";
                                        };

                                        let result = await bCtx.mint(pId, recipient, liquidNat, 0, justification);

                                        switch (result) {
                                            case (#ok(())) {
                                                ctx.buildResponse(#ok, #html(UI.renderSuccess("Jetons émis avec succès.", getToken(ctx))));
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
                                let ?bodyText = ctx.parseUtf8Body() else return ctx.buildResponse(#badRequest, #html(UI.renderError("Corps de requête manquant.")));
                                let form = decodeForm(bodyText);
                                let userIdOpt = getAuthenticatedUserId(ctx);

                                switch (userIdOpt) {
                                    case null {
                                        ctx.buildResponse(#unauthorized, #html(UI.renderError("Non autorisé.")));
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
                                                ctx.buildResponse(#ok, #html(UI.renderSuccess("Transfert réussi.", getToken(ctx))));
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
                                let ?bodyText = ctx.parseUtf8Body() else return ctx.buildResponse(#badRequest, #html(UI.renderError("Corps de requête manquant.")));
                                let form = decodeForm(bodyText);
                                let userIdOpt = getAuthenticatedUserId(ctx);

                                switch (userIdOpt) {
                                    case null {
                                        ctx.buildResponse(#unauthorized, #html(UI.renderError("Non autorisé.")));
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
                                                ctx.buildResponse(#ok, #html(UI.renderSuccess("Jetons stakés avec succès.", getToken(ctx))));
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
                                            ctx.buildResponse(#notFound, #html(UI.renderError("Projet introuvable dans le registre.")));
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
