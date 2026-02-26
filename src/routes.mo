import Router "mo:liminal/Router";
import RouteContext "mo:liminal/RouteContext";
import Liminal "mo:liminal";

module Routes {
    public func routerConfig(_canisterId : Text) : Router.Config {
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
                                        ctx.buildResponse(#unauthorized, #html("<html><body><h1>Unauthorized</h1><p>Missing or invalid NFC Tag</p></body></html>"));
                                    };
                                    case (?userId) {
                                        let html = "<html><body style='font-family: sans-serif; text-align: center; margin-top: 50px;'><h1>✅ NFC Scan Validated!</h1><p>Welcome to the PCARE Portal, " # userId # ".</p>
                                        <form action='/pcare/mint' method='POST'><input type='hidden' name='userId' value='" # userId # "'/><button type='submit'>Mint 100 Tokens</button></form>
                                        </body></html>";
                                        ctx.buildResponse(#ok, #html(html));
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
                                let userIdOpt = ctx.getQueryParam("userId");
                                switch (userIdOpt) {
                                    case null {
                                        ctx.buildResponse(#unauthorized, #html("<html><body><h1>Unauthorized</h1></body></html>"));
                                    };
                                    case (?userId) {
                                        // In a real app, we'd call the main actor. Here we just return success HTML for testing the routing flow.
                                        let html = "<html><body style='font-family: sans-serif; text-align: center; margin-top: 50px;'><h1>💰 Tokens Minted!</h1><p>Minted tokens for " # userId # ".</p><a href='/pcare?userId=" # userId # "'>Go Back</a></body></html>";
                                        ctx.buildResponse(#ok, #html(html));
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
