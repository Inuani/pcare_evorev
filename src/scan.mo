import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Array "mo:core/Array";
import Iter "mo:core/Iter";
import Char "mo:core/Char";
import Nat8 "mo:core/Nat8";
import Nat32 "mo:core/Nat32";
import Blob "mo:core/Blob";
import Sha256 "mo:sha2/Sha256";
import Debug "mo:core/Debug";

module {
    public func hexToNat(hexString : Text) : Nat {
        var result : Nat = 0;
        for (char in hexString.chars()) {
            if (Char.toNat32(char) >= Char.toNat32('0') and Char.toNat32(char) <= Char.toNat32('9')) {
                result := result * 16 + (Nat32.toNat(Char.toNat32(char)) - 48);
            } else if (Char.toNat32(char) >= Char.toNat32('A') and Char.toNat32(char) <= Char.toNat32('F')) {
                result := result * 16 + (Nat32.toNat(Char.toNat32(char)) - 55);
            } else if (Char.toNat32(char) >= Char.toNat32('a') and Char.toNat32(char) <= Char.toNat32('f')) {
                result := result * 16 + (Nat32.toNat(Char.toNat32(char)) - 87);
            } else {
                assert (false);
            };
        };
        return result;
    };

    public func subText(value : Text, indexStart : Nat, indexEnd : Nat) : Text {
        if (indexStart == 0 and indexEnd >= value.size()) {
            return value;
        } else if (indexStart >= value.size()) {
            return "";
        };

        var indexEndValid = indexEnd;
        if (indexEnd > value.size()) {
            indexEndValid := value.size();
        };

        var result : Text = "";
        var iter = Iter.toArray<Char>(value.chars());
        for (index in Nat.rangeInclusive(indexStart, indexEndValid - 1)) {
            result := result # Char.toText(iter[index]);
        };

        result;
    };

    public func getUid(url : Text) : ?Text {
        let full_query = Iter.toArray(Text.split(url, #char '?'));
        if (full_query.size() != 2) {
            return null;
        };

        let queries = Iter.toArray(Text.split(full_query[1], #char '&'));
        for (q in queries.vals()) {
            let parts = Iter.toArray(Text.split(q, #char '='));
            if (parts.size() == 2 and parts[0] == "uid") {
                return ?parts[1];
            };
        };

        return null;
    };

    public func scan(cmacs : [Text], url : Text, scan_count : Nat) : Nat {
        Debug.print("Scan.scan called with URL: " # url);
        let full_query = Iter.toArray(Text.split(url, #char '?'));
        if (full_query.size() != 2) {
            return 0;
        };

        let queries = Iter.toArray(Text.split(full_query[1], #char '&'));

        var counterOpt : ?Text = null;
        var cmacOpt : ?Text = null;

        for (q in queries.vals()) {
            let parts = Iter.toArray(Text.split(q, #char '='));
            if (parts.size() == 2) {
                if (parts[0] == "ctr") {
                    counterOpt := ?parts[1];
                } else if (parts[0] == "cmac") {
                    cmacOpt := ?parts[1];
                };
            };
        };

        let counter_str = switch (counterOpt) {
            case (?val) val;
            case null {
                Debug.print("CMAC parsing failed: Missing ctr parameter.");
                return 0;
            };
        };

        let cmac_str = switch (cmacOpt) {
            case (?val) val;
            case null {
                Debug.print("CMAC parsing failed: Missing cmac parameter.");
                return 0;
            };
        };

        var counter = hexToNat(counter_str);

        let input_bytes = Array.map(
            Text.toArray(cmac_str),
            func(c : Char) : Nat8 {
                Nat8.fromNat(Nat32.toNat(Char.toNat32(c)));
            },
        );

        let digest = Sha256.Digest(#sha256);
        digest.writeArray(input_bytes);
        let sha = Blob.toArray(digest.sum());

        if (counter > cmacs.size() or counter <= scan_count) {
            return 0;
        };

        var res = counter;

        for (i in Nat.rangeInclusive(0, sha.size() - 1)) {
            let shaByte = Nat8.toNat(sha[i]);
            let targetByte = hexToNat(subText(cmacs[counter - 1], i * 2, i * 2 + 2));
            if (shaByte != targetByte) {
                Debug.print("Byte mismatch at index " # Nat.toText(i) # ". Expected: " # Nat.toText(targetByte) # " Got: " # Nat.toText(shaByte));
                res := 0;
            };
        };

        return res;
    };
};
