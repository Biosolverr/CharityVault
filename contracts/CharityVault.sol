// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CharityVault
 * @notice Kickstarter-style crowdfunding on Base.
 *         Funds are locked until the goal is reached.
 *         If the deadline passes without reaching the goal,
 *         every contributor can reclaim their share.
 */
contract CharityVault {
    // ─── Types ────────────────────────────────────────────────────────────────

    enum Category { Medical, Event, OpenSource, NFT, Other }

    struct Campaign {
        uint256 id;
        address payable creator;
        string  title;
        string  description;
        string  imageUrl;          // IPFS / any URL
        Category category;
        uint256 goal;              // wei
        uint256 deadline;          // unix timestamp
        uint256 raised;            // wei collected so far
        bool    claimed;           // creator withdrew funds
        bool    cancelled;         // creator cancelled early
    }

    // ─── State ────────────────────────────────────────────────────────────────

    uint256 public campaignCount;

    /// campaignId → Campaign
    mapping(uint256 => Campaign) public campaigns;

    /// campaignId → contributor → amount
    mapping(uint256 => mapping(address => uint256)) public contributions;

    /// campaignId → list of unique contributors (for enumeration)
    mapping(uint256 => address[]) private _contributors;
    mapping(uint256 => mapping(address => bool)) private _hasContributed;

    // ─── Events ───────────────────────────────────────────────────────────────

    event CampaignCreated(
        uint256 indexed id,
        address indexed creator,
        string  title,
        uint256 goal,
        uint256 deadline,
        Category category
    );

    event ContributionMade(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount,
        uint256 totalRaised
    );

    event FundsClaimed(
        uint256 indexed campaignId,
        address indexed creator,
        uint256 amount
    );

    event RefundIssued(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );

    event CampaignCancelled(uint256 indexed campaignId);

    // ─── Errors ───────────────────────────────────────────────────────────────

    error NotCreator();
    error CampaignNotFound();
    error CampaignEnded();
    error CampaignNotEnded();
    error GoalNotReached();
    error GoalAlreadyReached();
    error AlreadyClaimed();
    error AlreadyCancelled();
    error NothingToRefund();
    error ZeroContribution();
    error InvalidGoal();
    error InvalidDeadline();
    error TransferFailed();

    // ─── Modifiers ────────────────────────────────────────────────────────────

    modifier campaignExists(uint256 _id) {
        if (_id == 0 || _id > campaignCount) revert CampaignNotFound();
        _;
    }

    modifier onlyCreator(uint256 _id) {
        if (msg.sender != campaigns[_id].creator) revert NotCreator();
        _;
    }

    // ─── External Functions ───────────────────────────────────────────────────

    /**
     * @notice Create a new fundraising campaign.
     * @param _title       Campaign title.
     * @param _description Short description / story.
     * @param _imageUrl    Cover image (IPFS CID or URL).
     * @param _category    One of the Category enum values.
     * @param _goal        Funding target in wei.
     * @param _durationDays Campaign duration in days (min 1, max 365).
     */
    function createCampaign(
        string  calldata _title,
        string  calldata _description,
        string  calldata _imageUrl,
        Category         _category,
        uint256          _goal,
        uint256          _durationDays
    ) external returns (uint256 id) {
        if (_goal == 0) revert InvalidGoal();
        if (_durationDays == 0 || _durationDays > 365) revert InvalidDeadline();

        unchecked { id = ++campaignCount; }

        campaigns[id] = Campaign({
            id:          id,
            creator:     payable(msg.sender),
            title:       _title,
            description: _description,
            imageUrl:    _imageUrl,
            category:    _category,
            goal:        _goal,
            deadline:    block.timestamp + _durationDays * 1 days,
            raised:      0,
            claimed:     false,
            cancelled:   false
        });

        emit CampaignCreated(id, msg.sender, _title, _goal, campaigns[id].deadline, _category);
    }

    /**
     * @notice Contribute ETH to a campaign.
     */
    function contribute(uint256 _id) external payable campaignExists(_id) {
        Campaign storage c = campaigns[_id];

        if (c.cancelled)               revert AlreadyCancelled();
        if (block.timestamp > c.deadline) revert CampaignEnded();
        if (msg.value == 0)            revert ZeroContribution();

        // Track unique contributors
        if (!_hasContributed[_id][msg.sender]) {
            _contributors[_id].push(msg.sender);
            _hasContributed[_id][msg.sender] = true;
        }

        contributions[_id][msg.sender] += msg.value;
        c.raised += msg.value;

        emit ContributionMade(_id, msg.sender, msg.value, c.raised);
    }

    /**
     * @notice Creator withdraws funds after deadline if goal is reached.
     */
    function claimFunds(uint256 _id)
        external
        campaignExists(_id)
        onlyCreator(_id)
    {
        Campaign storage c = campaigns[_id];

        if (c.cancelled)                  revert AlreadyCancelled();
        if (c.claimed)                    revert AlreadyClaimed();
        if (block.timestamp <= c.deadline) revert CampaignNotEnded();
        if (c.raised < c.goal)            revert GoalNotReached();

        c.claimed = true;
        uint256 amount = c.raised;

        (bool ok,) = c.creator.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit FundsClaimed(_id, msg.sender, amount);
    }

    /**
     * @notice Contributor reclaims their share if campaign failed or was cancelled.
     */
    function refund(uint256 _id) external campaignExists(_id) {
        Campaign storage c = campaigns[_id];

        bool failed    = block.timestamp > c.deadline && c.raised < c.goal;
        bool cancelled = c.cancelled;

        if (!failed && !cancelled) revert CampaignNotEnded();

        uint256 amount = contributions[_id][msg.sender];
        if (amount == 0) revert NothingToRefund();

        contributions[_id][msg.sender] = 0;

        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit RefundIssued(_id, msg.sender, amount);
    }

    /**
     * @notice Creator cancels before deadline (only if goal not yet reached).
     *         Contributors can then call refund().
     */
    function cancelCampaign(uint256 _id)
        external
        campaignExists(_id)
        onlyCreator(_id)
    {
        Campaign storage c = campaigns[_id];

        if (c.cancelled)                   revert AlreadyCancelled();
        if (c.claimed)                     revert AlreadyClaimed();
        if (block.timestamp > c.deadline)  revert CampaignEnded();

        c.cancelled = true;

        emit CampaignCancelled(_id);
    }

    // ─── View Functions ───────────────────────────────────────────────────────

    /**
     * @notice Returns full Campaign struct.
     */
    function getCampaign(uint256 _id)
        external
        view
        campaignExists(_id)
        returns (Campaign memory)
    {
        return campaigns[_id];
    }

    /**
     * @notice Returns all campaign IDs (paginated via offset/limit).
     */
    function getCampaigns(uint256 offset, uint256 limit)
        external
        view
        returns (Campaign[] memory result)
    {
        uint256 total = campaignCount;
        if (offset >= total) return new Campaign[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;

        result = new Campaign[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = campaigns[i + 1]; // IDs are 1-based
        }
    }

    /**
     * @notice Returns list of unique contributor addresses for a campaign.
     */
    function getContributors(uint256 _id)
        external
        view
        campaignExists(_id)
        returns (address[] memory)
    {
        return _contributors[_id];
    }

    /**
     * @notice Returns contribution amount for a specific contributor.
     */
    function getContribution(uint256 _id, address _contributor)
        external
        view
        returns (uint256)
    {
        return contributions[_id][_contributor];
    }

    /**
     * @notice Derive campaign status from state.
     * @return 0 = Active, 1 = Succeeded (claimable), 2 = Failed (refundable),
     *         3 = Claimed, 4 = Cancelled
     */
    function getStatus(uint256 _id)
        external
        view
        campaignExists(_id)
        returns (uint8)
    {
        Campaign storage c = campaigns[_id];
        if (c.cancelled) return 4;
        if (c.claimed)   return 3;
        if (block.timestamp <= c.deadline) return 0; // Active
        if (c.raised >= c.goal) return 1;            // Succeeded
        return 2;                                     // Failed
    }
}
