// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract ChainStateProtocol is ERC721URIStorage {
    //////////////////////
    //state variables
    //////////////////////
    using Counters for Counters.Counter;
    Counters.Counter public assetsTotalCount;

    //address with admin right for ChainState Protocol
    address payable internal administrator;

    //charge for an asset to be added to the protocol by an admin
    uint64 assetsListingFee;

    /// @dev structure of real estate assets
    struct AssetDetails {
        string assetURI;
        string assetName;
        string assetLocation;
        uint112 assetSalePrice;
        string[] assetProperties;
        address lister;
        address buyer;
        bool sold;
        AssetStatus status;
        uint256 totalAmountFromSales;
    }

    /// -----------------------------
    /// ----------- ENUMS -----------
    /// -----------------------------
    enum AssetStatus {
        BUYER_HAS_NOT_RECEIVED,
        BUYER_HAS_RECEIVED
    }

    //////////////////////
    //-----MAPPINGS-------
    //////////////////////
    mapping(uint256 => AssetDetails) idToAssets;
    mapping(address => AssetDetails[]) ownedAssets;

    //////////////////////
    //custom errors
    //////////////////////
    error notAdminError(string);
    error wrongAction(string);

    //////////////////////
    //events
    //////////////////////
    event AssetListed(
        string assetURI,
        string assetName,
        string assetLocation,
        uint112 assetSalePrice,
        string[] assetProperties
    );

    //event for ERC721 receiver
    event Received();

    /// -----------------------------------
    /// ----------- CONSTRUCTOR -----------
    /// -----------------------------------
    constructor(address payable admin, uint64 listingCharge)
        ERC721("ChainState Protocol", "CSP")
    {
        require(admin != address(0));

        administrator = admin;
        assetsListingFee = listingCharge;
    }

    /// ---------------------------------
    /// ----------- MODIFIERS -----------
    /// ---------------------------------

    modifier onlyAdmin() {
        if (msg.sender != administrator) {
            revert notAdminError("ChainState Protocol: Only administrator");
        }
        _;
    }

    ///@dev function to list an IRL asset on-chain,
    ///requires msg.sender to be administrator
    function listAsset(
        string memory assetURI,
        string memory assetName,
        string memory assetLocation,
        uint112 assetSalePrice,
        string[] memory assetProperties
    )
        external
        // uint16 maxNumberOfOwners
        onlyAdmin
    {
        if (assetProperties.length == 0) {
            revert wrongAction(
                "ChainState Protocol: Asset must have a unique property"
            );
        }

        if (assetSalePrice == 0) {
            revert wrongAction(
                "ChainState Protocol: Asset sale price must have worth"
            );
        }

        uint256 assetId = assetsTotalCount.current();
        assetsTotalCount.increment();

        AssetDetails storage AST = idToAssets[assetId];
        AST.assetURI = assetURI;
        AST.assetName = assetName;
        AST.assetLocation = assetLocation;
        AST.assetSalePrice = assetSalePrice;
        AST.assetProperties = assetProperties;
        AST.lister = msg.sender;
        AST.status = AssetStatus.BUYER_HAS_NOT_RECEIVED;
        AST.totalAmountFromSales = 0;

        emit AssetListed(
            assetURI,
            assetName,
            assetLocation,
            assetSalePrice,
            assetProperties
        );

        _safeMint(address(this), assetId);
        _setTokenURI(assetId, assetURI);
    }

    ///@dev function to buy an asset
    function buyAsset(uint256 _assetId) external payable {
        require(
            _assetId <= assetsTotalCount.current(),
            "ChainState Protocol: Invalid asset Id"
        );

        AssetDetails storage AST = idToAssets[_assetId];

        //require that the asset has been listed
        if (AST.lister != address(0)) {
            revert wrongAction("ChainState Protocol: Asset does not exist");
        }

        //require that the asset has not been sold
        if (AST.buyer != address(0)) {
            revert wrongAction(
                "ChainState Protocol: Asset has been sold already"
            );
        }
        assert(!AST.sold);

        require(
            msg.value == AST.assetSalePrice,
            "ChainState Protocol: Provide correct asset price"
        );

        AST.buyer = msg.sender;
        AST.sold = true;

        //mint asset as NFT for buyer for proof of ownership IRL
        _safeMint(msg.sender, _assetId);
    }

    /// @dev function to delivery confirmation of asset
    /// only called by admin after confirming handover od asset to
    /// buyer off-chain
    function setAssetStatus(uint256 _assetId) external onlyAdmin {
        require(
            _assetId <= assetsTotalCount.current(),
            "ChainState Protocol: Invalid asset Id"
        );

        AssetDetails storage AST = idToAssets[_assetId];

        //require that the asset has been sold
        if (AST.buyer == address(0)) {
            revert wrongAction(
                "ChainState Protocol: Asset has not been sold yet"
            );
        }

        require(AST.sold);

        require(
            AST.status == AssetStatus.BUYER_HAS_NOT_RECEIVED,
            "ChainState Protocol: Buyer already received asset off-chain"
        );

        AST.status = AssetStatus.BUYER_HAS_RECEIVED;
    }

    /// @dev Function for event creators to withdraw amount gotten from their ticket sale
    /*     function withdrawAmountFromTicketSale(uint256 _tokenId)
        public
        returns (
            string memory,
            uint256,
            string memory,
            uint256
        )
    {
        AssetDetails memory AST = idToAssets[_assetId];

        address assetLister = AST.ow;
        require(msg.sender == eventCreator, "Not event owner");

        require(_tokenId <= _tokenIdCounter.current(), "Token does not exist");

        require(
            idToListedEvent[_tokenId].isCurrentlyListed,
            "Ticket sale ended"
        );
        idToListedEvent[_tokenId].isCurrentlyListed = false;

        uint256 amount = idToListedEvent[_tokenId].totalAmountGottenFromSale;
        require(eventCreator != address(0), "Error: Invalid Ticket");
        require(amount > 0, "Error: No ticket sale yet, nothing to withdraw");

        (uint256 eventListingFee, uint256 remainingBalance) = this
            .getFeePercentage(amount);

        (bool success, ) = payable(owner_).call{value: eventListingFee}("");
        (bool tx, ) = payable(eventCreator).call{value: remainingBalance}("");

        require(success, "Failed to send");
        require(tx, "Failed to send");
        return (
            "Our fee:",
            eventListingFee,
            "Amount sent to event creator",
            remainingBalance
        );
    }
 */
    ///@dev function for ERC721 receiver, so our contract can receive NFT tokens using safe functions
    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external returns (bytes4) {
        _operator;
        _from;
        _tokenId;
        _data;
        emit Received();
        return 0x150b7a02;
    }

    fallback() external payable {}

    receive() external payable {}
}
