module Types {

    public type UserId = Text;
    public type ProjectId = Text;
    public type TokenId = Text;
    public type NfcUid = Text;

    public type User = {
        id : UserId;
        username : Text;
        active_nfc_uids : [NfcUid];
    };

    public type Balance = {
        liquid : Nat;
        staked : Nat;
    };

    public type MintRecord = {
        timestamp : Int;
        amount_liquid : Nat;
        justification : Text;
    };

    public type Project = {
        id : ProjectId;
        name : Text;
        current_supply : Nat;
        total_liquid : Nat;
        total_staked : Nat;
        lead_id : UserId;
        // Treasury allows an aggregator project to hold equity in other projects
        treasury : [(TokenId, Balance)];
    };

};
