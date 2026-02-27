import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Types "models/Types";

module UI {

    // --- HTML Boilerplate & Styling ---
    private let css = "
        :root {
            --bg-color: #f4f4f0;
            --text-color: #000000;
            --brand-color: #bbf7d0; /* Light Green */
            --accent-color: #e9d5ff; /* Light Violet */
            --card-bg: #ffffff;
            --border-radius: 0px;
            --border-width: 4px;
            --shadow: 6px 6px 0px #000000;
            --shadow-hover: 2px 2px 0px #000000;
        }
        body {
            font-family: 'Space Mono', 'Courier New', Courier, monospace;
            background-color: var(--bg-color);
            color: var(--text-color);
            margin: 0;
            padding: 0;
            display: flex;
            flex-direction: column;
            align-items: center;
        }
        header {
            width: 100%;
            background-color: var(--brand-color);
            padding: 20px 0;
            text-align: center;
            border-bottom: var(--border-width) solid #000;
            margin-bottom: 40px;
        }
        header h1 {
            margin: 0;
            font-size: 2.5rem;
            text-transform: uppercase;
            letter-spacing: -2px;
            font-weight: 900;
            color: #000;
        }
        .container {
            width: 90%;
            max-width: 800px;
            display: flex;
            flex-direction: column;
            gap: 30px;
        }
        .card {
            background-color: var(--card-bg);
            padding: 30px;
            border: var(--border-width) solid #000;
            box-shadow: var(--shadow);
            position: relative;
        }
        .card::before {
            content: '';
            position: absolute;
            top: -4px;
            left: -4px;
            width: 20px;
            height: 20px;
            background-color: var(--accent-color);
            border: var(--border-width) solid #000;
            z-index: 10;
        }
        .card h2 {
            margin-top: 0;
            color: var(--text-color);
            text-transform: uppercase;
            font-size: 1.8rem;
            font-weight: 900;
            border-bottom: var(--border-width) solid #000;
            padding-bottom: 10px;
            letter-spacing: -1px;
            margin-bottom: 20px;
        }
        .balance-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 15px 0;
            border-bottom: 2px solid #000;
        }
        .balance-item:last-child {
            border-bottom: none;
        }
        .token-name {
            font-weight: 900;
            text-transform: uppercase;
            font-size: 1.2rem;
            background-color: var(--brand-color);
            padding: 4px 10px;
            border: 2px solid #000;
        }
        .balance-amount {
            font-size: 1.3rem;
            font-weight: bold;
            background-color: #fff;
            padding: 4px 10px;
            border: 2px dashed #000;
        }
        .btn {
            background-color: var(--accent-color);
            color: #000;
            border: var(--border-width) solid #000;
            padding: 12px 24px;
            font-size: 1.1rem;
            font-weight: 900;
            text-transform: uppercase;
            cursor: pointer;
            box-shadow: var(--shadow);
            transition: all 0.1s ease-in-out;
            text-decoration: none;
            display: inline-block;
            font-family: inherit;
            margin-top: 10px;
        }
        .btn:hover {
            transform: translate(4px, 4px);
            box-shadow: var(--shadow-hover);
            background-color: var(--brand-color);
        }
        .btn-outline {
            background-color: #fff;
        }
        .form-group {
            margin-bottom: 20px;
        }
        .form-group label {
            display: block;
            margin-bottom: 8px;
            color: #000;
            font-weight: 900;
            font-size: 1rem;
            text-transform: uppercase;
        }
        input, select {
            width: 100%;
            padding: 12px;
            background-color: #fff;
            border: var(--border-width) solid #000;
            color: #000;
            box-sizing: border-box;
            font-family: inherit;
            font-size: 1.1rem;
            font-weight: bold;
        }
        input:focus, select:focus {
            outline: none;
            background-color: var(--brand-color);
        }
        .error-box {
            background-color: #fca5a5;
            border: var(--border-width) solid #000;
            padding: 20px;
            margin-bottom: 20px;
            box-shadow: var(--shadow);
            position: relative;
        }
        .error-box h3, .success-box h3 {
            margin-top: 0;
            text-transform: uppercase;
            font-weight: 900;
            border-bottom: 2px solid #000;
            padding-bottom: 5px;
        }
        .success-box {
            background-color: var(--brand-color);
            border: var(--border-width) solid #000;
            padding: 20px;
            margin-bottom: 20px;
            box-shadow: var(--shadow);
            position: relative;
        }
    ";

    private func documentHead(title : Text) : Text = "<!DOCTYPE html>\n" #
    "<html>\n" #
    "<head>\n" #
    "<meta charset='UTF-8'>\n" #
    "<meta name='viewport' content='width=device-width, initial-scale=1.0'>\n" #
    "<title>" # title # "</title>\n" #
    "<style>\n" # css # "</style>\n" #
    "</head>\n" #
    "<body>\n";

    private let documentTail = "</body></html>";

    private func header(title : Text) : Text = "<header><h1>" # title # "</h1></header>\n";

    // --- Page Renderers ---

    public func renderError(message : Text) : Text = documentHead("PCARE Error") #
    header("Access Denied") #
    "<div class='container'>\n" #
    "  <div class='error-box'>\n" #
    "    <h3>Verification Failed</h3>\n" #
    "    <p>" # message # "</p>\n" #
    "  </div>\n" #
    "</div>\n" #
    documentTail;

    public func renderSuccess(message : Text, tokenValue : Text) : Text = documentHead("Success - PCARE") #
    header("Transaction Complete") #
    "<div class='container'>\n" #
    "  <div class='success-box'>\n" #
    "    <h3>Success</h3>\n" #
    "    <p>" # message # "</p>\n" #
    "  </div>\n" #
    "  <a href='/pcare?token=" # tokenValue # "' class='btn btn-outline' style='text-align: center;'>Return to Dashboard</a>\n" #
    "</div>\n" #
    documentTail;

    public func renderDashboard(
        user : Types.User,
        balances : [(Types.ProjectId, Types.Balance)],
        allProjects : [Types.Project],
        tokenValue : Text,
    ) : Text {
        var html = documentHead("PCARE Dashboard") #
        header(user.username) #
        "<div class='container'>\n";

        // 1. Balances Card
        html := html # "<div class='card'>\n";
        html := html # "<h2>Your Assets</h2>\n";
        if (balances.size() == 0) {
            html := html # "<p style='color: #888;'>No assets found. Mint some tokens!</p>\n";
        } else {
            for ((projId, bal) in balances.vals()) {
                html := html # "<div class='balance-item'>\n";
                html := html # "  <span class='token-name'>" # projId # "</span>\n";
                html := html # "  <div style='text-align: right;'>\n";
                html := html # "    <div class='balance-amount'>" # Nat.toText(bal.liquid) # " <span style='font-size: 0.8rem; color: #aaa'>Liquid</span></div>\n";
                html := html # "    <div class='balance-amount'>" # Nat.toText(bal.staked) # " <span style='font-size: 0.8rem; color: #aaa'>Staked</span></div>\n";
                html := html # "  </div>\n";
                html := html # "</div>\n";
            };
        };
        html := html # "</div>\n";

        // Generate Project Options for Dropdowns
        var projectOptions = "";
        var ledProjectsOptions = "";
        for (proj in allProjects.vals()) {
            let optionHtml = "<option value='" # proj.id # "'>" # proj.name # " (" # proj.id # ")</option>";
            projectOptions := projectOptions # optionHtml;
            if (proj.lead_id == user.id) {
                ledProjectsOptions := ledProjectsOptions # optionHtml;
            };
        };
        if (projectOptions == "") {
            projectOptions := "<option value=''>No projects available</option>";
        };

        // 2. Action: Mint (Only show projects led by this user, but for testing we show all or let them type)
        // Note: For full security, backend verifies if user is lead.
        html := html # "<div class='card'>\n";
        html := html # "<h2>Protocol Operations</h2>\n";
        html := html # "<p style='color: #aaa; margin-bottom: 20px; font-size: 0.9rem;'>Execute verifiable on-chain protocol actions.</p>\n";

        // Stake Form
        html := html # "<h3>Stake Influence</h3>\n";
        html := html # "<form action='/pcare/stake?token=" # tokenValue # "' method='POST' style='margin-bottom: 30px;'>\n";
        html := html # "  <div class='form-group'>\n";
        html := html # "    <label>Select Project</label>\n";
        html := html # "    <select name='projectId' required>\n" # projectOptions # "</select>\n";
        html := html # "  </div>\n";
        html := html # "  <div class='form-group'>\n";
        html := html # "    <label>Amount to Stake</label>\n";
        html := html # "    <input type='number' name='amount' min='1' required placeholder='e.g. 50'/>\n";
        html := html # "  </div>\n";
        html := html # "  <button type='submit' class='btn'>Submit Stake</button>\n";
        html := html # "</form>\n";

        // Pay Form
        html := html # "<h3>Transfer Tokens</h3>\n";
        html := html # "<form action='/pcare/pay?token=" # tokenValue # "' method='POST' style='margin-bottom: 30px;'>\n";
        html := html # "  <div class='form-group'>\n";
        html := html # "    <label>Select Token</label>\n";
        html := html # "    <select name='projectId' required>\n" # projectOptions # "</select>\n";
        html := html # "  </div>\n";
        html := html # "  <div class='form-group'>\n";
        html := html # "    <label>Recipient Username</label>\n";
        html := html # "    <input type='text' name='recipientId' required placeholder='e.g. LX'/>\n";
        html := html # "  </div>\n";
        html := html # "  <div class='form-group'>\n";
        html := html # "    <label>Amount</label>\n";
        html := html # "    <input type='number' name='amount' min='1' required placeholder='e.g. 10'/>\n";
        html := html # "  </div>\n";
        html := html # "  <button type='submit' class='btn btn-outline'>Transfer</button>\n";
        html := html # "</form>\n";

        // Mint Form (Only visible to Project Leads)
        if (ledProjectsOptions != "") {
            html := html # "<h3>Mint Rewards (Leads Only)</h3>\n";
            html := html # "<form action='/pcare/mint?token=" # tokenValue # "' method='POST'>\n";
            html := html # "  <div class='form-group'>\n";
            html := html # "    <label>Select Project</label>\n";
            html := html # "    <select name='projectId' required>\n" # ledProjectsOptions # "</select>\n";
            html := html # "  </div>\n";
            html := html # "  <div class='form-group'>\n";
            html := html # "    <label>Recipient Username (Leave blank to mint to self)</label>\n";
            html := html # "    <input type='text' name='recipientId' placeholder='e.g. LX'/>\n";
            html := html # "  </div>\n";
            html := html # "  <div class='form-group'>\n";
            html := html # "    <label>Liquid Amount</label>\n";
            html := html # "    <input type='number' name='liquid' min='0' value='100' required/>\n";
            html := html # "  </div>\n";
            html := html # "  <button type='submit' class='btn'>Authorize Mint</button>\n";
            html := html # "</form>\n";
        };

        html := html # "</div>\n";

        html := html # "</div>\n"; // End container
        html := html # documentTail;

        html;
    };
};
