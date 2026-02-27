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
import UI "ui";

module Routes {

    public type BackendCtx = {
        mint : (Types.ProjectId, Text, Nat, Nat, Text) -> async Result.Result<(), Text>;
        pay : (Types.UserId, Text, Types.ProjectId, Nat) -> async Result.Result<(), Text>;
        stake : (Types.UserId, Types.ProjectId, Nat) -> async Result.Result<(), Text>;
        getUser : (Types.UserId) -> ?Types.User;
        getProjects : () -> [Types.Project];
        getBalances : (Types.UserId) -> [(Types.ProjectId, Types.Balance)];
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
                    "/",
                    #query_(
                        func(ctx : RouteContext.RouteContext) : Liminal.HttpResponse {
                            let html = "<html><body><h1>Evorev NFC System Active</h1></body></html>";
                            ctx.buildResponse(#ok, #html(html));
                        }
                    ),
                ),
                Router.get(
                    "/pcare",
                    #update(
                        #async_(
                            func(ctx : RouteContext.RouteContext) : async* Liminal.HttpResponse {
                                let userIdOpt = ctx.getQueryParam("userId");
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
                                                ctx.buildResponse(#ok, #html(UI.renderDashboard(user, balances, projects)));
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
                                let userIdOpt = getFormValue(form, "userId");

                                switch (userIdOpt) {
                                    case null {
                                        ctx.buildResponse(#unauthorized, #html(UI.renderError("Unauthorized.")));
                                    };
                                    case (?userId) {
                                        let projId = getFormValue(form, "projectId");
                                        let recIdRaw = getFormValue(form, "recipientId");
                                        let liq = getFormValue(form, "liquid");

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

                                        let result = await bCtx.mint(pId, recipient, liquidNat, 0, "Dashboard Mint");

                                        switch (result) {
                                            case (#ok(())) {
                                                ctx.buildResponse(#ok, #html(UI.renderSuccess("Successfully minted tokens.", userId)));
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
                                let userIdOpt = getFormValue(form, "userId");

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
                                                ctx.buildResponse(#ok, #html(UI.renderSuccess("Transfer successful.", userId)));
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
                                let userIdOpt = getFormValue(form, "userId");

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
                                                ctx.buildResponse(#ok, #html(UI.renderSuccess("Successfully staked tokens.", userId)));
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
                    "/{path}",
                    #query_(
                        func(ctx) : Liminal.HttpResponse {
                            ctx.buildResponse(#notFound, #error(#message("Not found")));
                        }
                    ),
                ),
            ];
        };
    };
};
