import Types "Types";
import Map "mo:map/Map";
import Text "mo:core/Text";

module {
    public type AppState = {
        var users : Map.Map<Types.UserId, Types.User>;
        var projects : Map.Map<Types.ProjectId, Types.Project>;
        var nfc_mapping : Map.Map<Types.NfcUid, Types.UserId>;
        var ledger : Map.Map<(Text, Types.TokenId), Types.Balance>;
    };

    public func init() : AppState {
        {
            var users = Map.new<Types.UserId, Types.User>();
            var projects = Map.new<Types.ProjectId, Types.Project>();
            var nfc_mapping = Map.new<Types.NfcUid, Types.UserId>();
            var ledger = Map.new<(Text, Types.TokenId), Types.Balance>();
        };
    };
};
