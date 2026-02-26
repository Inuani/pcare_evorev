import Router "mo:liminal/Router";
import RouteContext "mo:liminal/RouteContext";
import Liminal "mo:liminal";

module Routes {
    public func routerConfig(_canisterId : Text) : Router.Config {
        {
            prefix = null;
            identityRequirement = null;
            routes = [
                Router.getQuery(
                    "/",
                    func(ctx : RouteContext.RouteContext) : Liminal.HttpResponse {
                        let html = "<html><body><h1>Evorev NFC System Active</h1></body></html>";
                        ctx.buildResponse(#ok, #html(html));
                    },
                ),
                Router.getQuery(
                    "/pcare",
                    func(ctx : RouteContext.RouteContext) : Liminal.HttpResponse {
                        let html = "<html><body style='font-family: sans-serif; text-align: center; margin-top: 50px;'><h1>✅ NFC Scan Validated!</h1><p>Welcome to the PCARE Portal.</p></body></html>";
                        ctx.buildResponse(#ok, #html(html));
                    },
                ),
                Router.getQuery(
                    "/{path}",
                    func(ctx) : Liminal.HttpResponse {
                        ctx.buildResponse(#notFound, #error(#message("Not found")));
                    },
                ),
            ];
        };
    };
};
