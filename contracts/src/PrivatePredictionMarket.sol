// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PrivatePredictionMarket
 * @notice Commit-reveal prediction market settled by Chainlink CRE
 */

contract PrivatePredictionMarket {

    enum Prediction { Yes, No }
    enum MarketState { Open, Resolving, RevealPhase, Settled }

    struct Market {
        string question;
        uint256 deadline;
        uint256 revealDeadline;
        MarketState state;
        Prediction outcome;
        uint256 totalStake;
        uint256 yesPool;
        uint256 noPool;
        bool finalized;
    }

    struct Commitment {
        bytes32 hash;
        uint256 stake;
        bool revealed;
        Prediction prediction;
        bool claimed;
    }

    address public immutable forwarder;
    address public owner;
    uint256 public marketCount;

    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => bool)) public isAllowed;
    mapping(uint256 => mapping(address => Commitment)) public commitments;

    event MarketCreated(uint256 indexed marketId, string question, uint256 deadline);
    event BetCommitted(uint256 indexed marketId, address indexed participant, uint256 stake);
    event SettlementRequested(uint256 indexed marketId, string question);
    event MarketSettled(uint256 indexed marketId, uint8 outcome);
    event RevealPhaseFinalized(uint256 indexed marketId, uint256 yesPool, uint256 noPool);
    event WinningsClaimed(uint256 indexed marketId, address indexed winner, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyForwarder() {
        require(
            msg.sender == forwarder || msg.sender == owner,
            "Not forwarder"
        );
        _;
    }

    modifier onlyAllowed(uint256 id) {
        require(isAllowed[id][msg.sender], "Not allowed");
        _;
    }

    constructor(address _forwarder) {
        forwarder = _forwarder;
        owner = msg.sender;
    }

    /**
     * CRE entrypoint
     * Forwarder calls: onReport(metadata, report)
     *
     * report encodes:
     *
     * CREATE MARKET
     * (uint8 instr, string question, uint256 deadline, address[] participants)
     *
     * SETTLE MARKET
     * (uint8 instr, uint256 marketId, uint8 outcome)
     */
    function onReport(
        bytes calldata,
        bytes calldata report
    ) external onlyForwarder {

        uint8 instr = uint8(bytes1(report[0]));

        if (instr == 0) {

            (
                ,
                string memory question,
                uint256 deadline,
                address[] memory participants
            ) = abi.decode(
                report,
                (uint8, string, uint256, address[])
            );

            _createMarket(question, deadline, participants);

        } else if (instr == 1) {

            (
                ,
                uint256 marketId,
                uint8 outcome
            ) = abi.decode(
                report,
                (uint8, uint256, uint8)
            );

            _settleMarket(marketId, outcome);

        } else {
            revert("Unknown instruction");
        }
    }

    function _createMarket(
        string memory question,
        uint256 deadline,
        address[] memory participants
    ) internal {

        require(deadline > block.timestamp, "Deadline must be future");

        uint256 marketId = marketCount++;

        markets[marketId] = Market({
            question: question,
            deadline: deadline,
            revealDeadline: 0,
            state: MarketState.Open,
            outcome: Prediction.Yes,
            totalStake: 0,
            yesPool: 0,
            noPool: 0,
            finalized: false
        });

        for (uint256 i = 0; i < participants.length; i++) {
            isAllowed[marketId][participants[i]] = true;
        }

        emit MarketCreated(marketId, question, deadline);
    }

    function _settleMarket(
        uint256 marketId,
        uint8 outcomeValue
    ) internal {

        require(outcomeValue <= 1, "Invalid outcome");

        Market storage market = markets[marketId];

        require(
            market.state == MarketState.Resolving,
            "Not resolving"
        );

        market.outcome = Prediction(outcomeValue);
        market.state = MarketState.RevealPhase;
        market.revealDeadline = block.timestamp + 24 hours;

        emit MarketSettled(marketId, outcomeValue);
    }

    function commitBet(
        uint256 marketId,
        bytes32 commitmentHash
    )
        external
        payable
        onlyAllowed(marketId)
    {

        Market storage market = markets[marketId];

        require(market.state == MarketState.Open, "Market closed");
        require(block.timestamp < market.deadline, "Deadline passed");
        require(msg.value > 0, "Stake required");
        require(commitments[marketId][msg.sender].stake == 0, "Already committed");

        commitments[marketId][msg.sender] = Commitment({
            hash: commitmentHash,
            stake: msg.value,
            revealed: false,
            prediction: Prediction.Yes,
            claimed: false
        });

        market.totalStake += msg.value;

        emit BetCommitted(marketId, msg.sender, msg.value);
    }

    function requestSettlement(uint256 marketId) external {

        Market storage market = markets[marketId];

        require(market.state == MarketState.Open, "Already resolving");
        require(block.timestamp >= market.deadline, "Deadline not reached");

        market.state = MarketState.Resolving;

        emit SettlementRequested(marketId, market.question);
    }

    function revealBet(
        uint256 marketId,
        Prediction prediction,
        bytes32 salt
    )
        external
        onlyAllowed(marketId)
    {

        Market storage market = markets[marketId];

        require(market.state == MarketState.RevealPhase, "Not reveal phase");
        require(block.timestamp < market.revealDeadline, "Reveal closed");

        Commitment storage c = commitments[marketId][msg.sender];

        require(c.stake > 0, "No commitment");
        require(!c.revealed, "Already revealed");

        bytes32 expectedHash =
            keccak256(abi.encodePacked(prediction, salt, msg.sender));

        require(expectedHash == c.hash, "Hash mismatch");

        c.revealed = true;
        c.prediction = prediction;

        if (prediction == Prediction.Yes) {
            market.yesPool += c.stake;
        } else {
            market.noPool += c.stake;
        }
    }

    function finalizeRevealPhase(uint256 marketId)
        external
        onlyOwner
    {

        Market storage market = markets[marketId];

        require(market.state == MarketState.RevealPhase, "Wrong state");
        require(block.timestamp >= market.revealDeadline, "Reveal open");
        require(!market.finalized, "Already finalized");

        market.state = MarketState.Settled;
        market.finalized = true;

        emit RevealPhaseFinalized(
            marketId,
            market.yesPool,
            market.noPool
        );
    }

    function claim(uint256 marketId)
        external
        onlyAllowed(marketId)
    {

        Market storage market = markets[marketId];

        require(market.state == MarketState.Settled, "Not settled");
        require(market.finalized, "Reveal not finalized");

        Commitment storage c = commitments[marketId][msg.sender];

        require(c.revealed, "Must reveal");
        require(c.prediction == market.outcome, "Not winner");
        require(!c.claimed, "Already claimed");
        require(c.stake > 0, "No stake");

        uint256 winnerPool =
            market.outcome == Prediction.Yes
            ? market.yesPool
            : market.noPool;

        uint256 loserPool = market.totalStake - winnerPool;

        uint256 payout =
            c.stake + (c.stake * loserPool) / winnerPool;

        c.claimed = true;

        (bool success,) = payable(msg.sender).call{value:payout}("");

        require(success, "Transfer failed");

        emit WinningsClaimed(marketId, msg.sender, payout);
    }

    function getMarket(uint256 marketId)
        external
        view
        returns (Market memory)
    {
        return markets[marketId];
    }

    function getCommitment(uint256 marketId, address participant)
        external
        view
        returns (Commitment memory)
    {
        return commitments[marketId][participant];
    }
}