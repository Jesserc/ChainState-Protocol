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
    uint64 assetsListingCharge;

    /// @dev structure of real estate assets
    struct AssetDetails {
        string assetURI;
        string assetName;
        string assetLocation;
        uint112 assetSalePrice;
        string[] properties;
        address[] fractionalOwners; //individual fraction owners will have their unique balance through a mapping
        uint16 maxNumberOfOwners;
        uint16 totalOwners;
        uint256 totalAmountFromSales;
    }

    //////////////////////
    //mappings
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
        string[] properties,
        uint16 maxNumberOfOwners,
        uint16 totalOwners,
        uint256 totalAmountFromSales
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
        assetsListingCharge = listingCharge;
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
        address lister,
        string memory assetURI,
        string memory assetName,
        string memory assetLocation,
        uint112 assetSalePrice,
        string[] memory properties,
        uint16 maxNumberOfOwners
    ) external onlyAdmin {
        if (properties.length == 0) {
            revert wrongAction(
                "ChainState Protocol: Asset must have a unique property"
            );
        }

        if (assetSalePrice == 0) {
            revert wrongAction(
                "ChainState Protocol: Asset sale price must have worth"
            );
        }

        require(
            maxNumberOfOwners > 0,
            "ChainState Protocol: Max number of owners can't be zero"
        );

        uint256 assetId = assetsTotalCount.current();
        assetsTotalCount.increment();

        AssetDetails storage AST = idToAssets[assetId];
        AST.assetURI = assetURI;
        AST.assetName = assetName;
        AST.assetLocation = assetLocation;
        AST.assetSalePrice = assetSalePrice;
        AST.properties = properties;
        AST.fractionalOwners[0] = lister;
        AST.maxNumberOfOwners = maxNumberOfOwners;
        AST.totalOwners = 1;
        AST.totalAmountFromSales = 0;

        emit AssetListed(
            assetURI,
            assetName,
            assetLocation,
            assetSalePrice,
            properties,
            maxNumberOfOwners,
            1,
            0
        );

        _safeMint(address(this), assetId);
        _setTokenURI(assetId, assetURI);
    }

    ///@dev function to buy a fraction of an asset or whole asset
    function buyAsset(uint256 _assetId) external payable {
        require(
            _assetId <= assetsTotalCount.current(),
            "ChainState Protocol: Invalid asset Id"
        );

        AssetDetails storage AST = idToAssets[_assetId];

        assert(AST.fractionalOwners[0] != address(0));

        if (AST.fractionalOwners.length <= AST.maxNumberOfOwners) {
            revert wrongAction(
                "ChainState Protocol: Max number of asset owners reached"
            );
        }

        require(
            msg.value == AST.assetSalePrice,
            "ChainState Protocol: Provide correct asset price"
        );
        AST.totalOwners += 1;
        AST.fractionalOwners.push(msg.sender);

        //mint asset as NFT for buyer for proof of ownership IRL
        _safeMint(msg.sender, _assetId);
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
