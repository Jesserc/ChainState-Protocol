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
    uint64 assetsListingFeePercentage;

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
    /// asset id => asset fee charged
    mapping(uint256 => uint256) assetFeeCharged;
    /// asset id => asset fee charged
    mapping(uint256 => uint256) assetFeeCharged;

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
    constructor(address payable admin, uint64 listingPercentage)
        ERC721("ChainState Protocol", "CSP")
    {
        require(admin != address(0));

        administrator = admin;
        assetsListingFeePercentage = listingPercentage;
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
        AST.assetSalePrice = assetSalePrice * 1 ether;
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

    /// @dev function to get all asset
    function getAllAssets() external view {
        AssetDetails[] memory allAssets = new AssetDetails[](
            assetsTotalCount.current()
        );

        uint256 currentItem;

        for (uint256 i; i < allAssets.length; ) {
            AssetDetails storage assets = idToAssets[i];
            allAssets[currentItem] = assets;
            currentItem += 1;

            unchecked {
                ++i;
            }
        }
    }

    function getMyAssets() external view {
        AssetDetails[] memory allAssets = new AssetDetails[](
            assetsTotalCount.current()
        );

        uint256 myItemCount;
        uint256 currentItem;

        for (uint256 i; i < allAssets.length; ) {
            if (idToAssets[i].buyer == msg.sender) {
                myItemCount += 1;
            }

            unchecked {
                ++i;
            }
        }

        AssetDetails[] memory myAssets = new AssetDetails[](myItemCount);

        for (uint256 i; i < myAssets.length; ) {
            AssetDetails storage assets = idToAssets[i];
            myAssets[currentItem] = assets;
            currentItem += 1;

            unchecked {
                ++i;
            }
        }
    }

    /// @dev internal function to fulfill payments for asset listers(only called by the admin)
    /// after confirming that an asset has been received by buyer off-chain

    function fulfillPayments(uint256 _assetId) internal {
        uint256 assetPrice;
        uint256 newAssetPrice;

        require(
            _assetId <= assetsTotalCount.current(),
            "ChainState Protocol: Invalid asset Id"
        );

        AssetDetails storage AST = idToAssets[_assetId];
        require(
            AST.status == AssetStatus.BUYER_HAS_RECEIVED,
            "ChainState Protocol: Buyer not received asset off-chain"
        );

        assetPrice = AST.assetSalePrice;
        newAssetPrice = (assetPrice * assetsListingFeePercentage) / 10_000;
    }

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
