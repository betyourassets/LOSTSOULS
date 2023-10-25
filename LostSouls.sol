// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./Counters.sol";

interface IERC721 {
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

interface IERC2981 {
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount);
}

contract LostSouls is IERC2981, ERC721Enumerable, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    // Royalty details
    uint256 private _royaltyPercentage = 5; // 5% DEFAULT ROYALTY

    address public constant LIL_HOTTIES_ADDRESS = 0x090BA74c1535DBaf3EDcD5CF98A986CE892815D0; // UNCHANGEABLE LIL HOTTIES CONTRACT ADDRESS
    address private _royaltyReceiver;

    uint256 public constant MAX_MINT = 1500;
    uint256 public phase1Timestamp;
    uint256 public phase2Timestamp;
    uint256 public phase3Timestamp;
    uint256 public phase4Timestamp;
    uint256 public phase1ClosingTimestamp;
    uint256 public phase2ClosingTimestamp;
    uint256 public phase3ClosingTimestamp;
    uint256 public phase4ClosingTimestamp;
    uint256 public phase1ReservedSupply;
    uint256 public phase2ReservedSupply;

    enum Phase { NONE, PHASE1, PHASE2, PHASE3, PHASE4, RESERVE_SUPPLY }

    Phase public currentPhase = Phase.NONE;
    bool public reservedSupplyReleased = false;

    mapping(uint => bool) public lostSoulMinted;
    mapping(Phase => uint256) public phaseClosingTimestamps;
    mapping(uint256 => bool) public phase1RedeemedTokenIds;
    mapping(uint256 => bool) public phase2RedeemedTokenIds;
    mapping(uint256 => bool) public phase3RedeemedTokenIds;
    mapping(Phase => uint256) public phaseMintPrices;
    mapping(Phase => mapping(uint256 => bool)) public phaseTokenIds;
    mapping(uint256 => string) private _tokenURIs;

    struct Artwork {
        string uri;
        uint256 maxSupply;
        uint256 currentSupply;
    }

    Artwork[] public artworks;

    // Added variables to track reserve supply status
    uint256 public phase1ReservedMinted = 0;
    uint256 public phase2ReservedMinted = 0;
    
    // Added variables to track public supply status
    uint256 public phase3And4Minted = 0;

    modifier onlyAdmin() {
        require(msg.sender == owner() || msg.sender == _royaltyReceiver, "Only the admin or royalty receiver can perform this action");
        _;
    }

    constructor(address royaltyReceiver) ERC721("LostSouls", "LS") {
        _royaltyReceiver = royaltyReceiver;
        phaseMintPrices[Phase.PHASE1] = 0.00 ether;
        phaseMintPrices[Phase.PHASE2] = 0.015 ether;
        phaseMintPrices[Phase.PHASE3] = 0.025 ether;
        phaseMintPrices[Phase.PHASE4] = 0.035 ether;

        phase1ReservedSupply = 99;
        phase2ReservedSupply = 510;
    }

    // Function to set the opening timestamps for each phase
    function setPhaseTimestamps(uint256 _phase1Timestamp, uint256 _phase2Timestamp, uint256 _phase3Timestamp, uint256 _phase4Timestamp) external onlyAdmin {
        phase1Timestamp = _phase1Timestamp;
        phase2Timestamp = _phase2Timestamp;
        phase3Timestamp = _phase3Timestamp;
        phase4Timestamp = _phase4Timestamp;
    }

    // Function to set the closing timestamps for each phase
    function setPhaseClosingTimestamps(uint256 _phase1ClosingTimestamp, uint256 _phase2ClosingTimestamp, uint256 _phase3ClosingTimestamp, uint256 _phase4ClosingTimestamp) external onlyAdmin {
        require(_phase1ClosingTimestamp >= block.timestamp, "Invalid Phase 1 closing timestamp");
        require(_phase2ClosingTimestamp >= block.timestamp, "Invalid Phase 2 closing timestamp");
        require(_phase3ClosingTimestamp >= block.timestamp, "Invalid Phase 3 closing timestamp");
        require(_phase4ClosingTimestamp >= block.timestamp, "Invalid Phase 4 closing timestamp");

        phase1ClosingTimestamp = _phase1ClosingTimestamp;
        phase2ClosingTimestamp = _phase2ClosingTimestamp;
        phase3ClosingTimestamp = _phase3ClosingTimestamp;
        phase4ClosingTimestamp = _phase4ClosingTimestamp;
    }

    function setRequiredTokensForPhase(Phase _phase, uint256[] calldata _tokenIds) external onlyAdmin {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            phaseTokenIds[_phase][_tokenIds[i]] = true;
        }
    }

    function getRequiredTokensForPhase(Phase _phase) public view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < MAX_MINT; i++) {
            if (phaseTokenIds[_phase][i]) {
                count++;
            }
        }

        uint256[] memory tokenIds = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < MAX_MINT; i++) {
            if (phaseTokenIds[_phase][i]) {
                tokenIds[index] = i;
                index++;
            }
        }

        return tokenIds;
    }

    function updateCurrentPhase() external onlyAdmin {
        if (block.timestamp > phase4Timestamp) {
            currentPhase = Phase.PHASE4;
        } else if (block.timestamp > phase3Timestamp) {
            currentPhase = Phase.PHASE3;
        } else if (block.timestamp > phase2Timestamp) {
            currentPhase = Phase.PHASE2;
        } else if (block.timestamp > phase1Timestamp) {
            currentPhase = Phase.PHASE1;
        } else {
            currentPhase = Phase.NONE;
        }
    }

    function getMintPriceForPhase() public view returns (uint256) {
        return phaseMintPrices[currentPhase];
    }

    function getPhase1ReservedSupply() public view returns (uint256) {
        return phase1ReservedSupply;
    }

    function getPhase2ReservedSupply() public view returns (uint256) {
        return phase2ReservedSupply;
    }
    function getRedeemedPhasesForTokenIds(uint256[] calldata _lilHottiesTokenIds) public view returns (Phase[][] memory) {
        Phase[][] memory redeemedPhases = new Phase[][](_lilHottiesTokenIds.length);

        for (uint256 i = 0; i < _lilHottiesTokenIds.length; i++) {
            uint256 phasesCount = 0;
            if (phase1RedeemedTokenIds[_lilHottiesTokenIds[i]]) {
                phasesCount++;
            }
            if (phase2RedeemedTokenIds[_lilHottiesTokenIds[i]]) {
                phasesCount++;
            }
            if (phase3RedeemedTokenIds[_lilHottiesTokenIds[i]]) {
                phasesCount++;
            }
            // Initialize an array to store the redeemed phases for this token
            Phase[] memory phases = new Phase[](phasesCount);
            uint256 index = 0;
            if (phase1RedeemedTokenIds[_lilHottiesTokenIds[i]]) {
                phases[index] = Phase.PHASE1;
                index++;
            }
            if (phase2RedeemedTokenIds[_lilHottiesTokenIds[i]]) {
                phases[index] = Phase.PHASE2;
                index++;
            }
            if (phase3RedeemedTokenIds[_lilHottiesTokenIds[i]]) {
                phases[index] = Phase.PHASE3;
            }
            // Assign the array of redeemed phases for this token
            redeemedPhases[i] = phases;
        }

        return redeemedPhases;
    }

    function _getRandomArtworkIndex(uint256 salt) internal view returns (uint256) {
        uint256 rand = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender, salt))) % artworks.length;
        return rand;
    }

    function mintLostSouls(uint256[] calldata _lilHottiesTokenIds, uint256 _numLostSouls, uint8 mintPhase) external payable nonReentrant {
        require(_numLostSouls > 0, "Number of Lost Souls must be greater than zero");

        // Check if the current phase is after the mint phase
        require(currentPhase >= Phase(mintPhase), "Minting for this phase has not started yet");

        // Calculate the required price for the specified mint phase
        uint256 requiredPrice = phaseMintPrices[Phase(mintPhase)];

        // Check if the user sent the correct amount of Ether
        require(msg.value == requiredPrice * _numLostSouls, "Incorrect amount of Ether sent");

// Phase 1 Minting Requirements
 if (mintPhase == uint8(Phase.PHASE1)) {
    require(block.timestamp >= phase1Timestamp, "Phase 1 minting has not started yet");
    require(block.timestamp <= phase1ClosingTimestamp, "Phase 1 minting has ended");
        require(phase1ReservedMinted + _numLostSouls <= 99, "Exceeded Phase 1 reserve supply");
        require(_lilHottiesTokenIds.length == _numLostSouls, "Mismatch in the number of tokens and Lost Souls to mint.");
        require(totalSupply() + _numLostSouls <= MAX_MINT, "Exceeded maximum supply");

        // Check if Lil Hotties token IDs have already been redeemed in Phase 1
        for (uint256 i = 0; i < _lilHottiesTokenIds.length; i++) {
            require(phaseTokenIds[Phase.PHASE1][_lilHottiesTokenIds[i]], "Invalid Lil Hotties token for Phase 1");
            require(!phase1RedeemedTokenIds[_lilHottiesTokenIds[i]], "This token ID has already been redeemed in Phase 1.");
        }

        // Phase 1 minting logic
        for (uint256 i = 0; i < _lilHottiesTokenIds.length; i++) {
            _mintLostSoul(_lilHottiesTokenIds[i], i);
        }
    }

// Phase 2 Minting Requirements
else if (mintPhase == uint8(Phase.PHASE2)) {
    require(block.timestamp >= phase2Timestamp, "Phase 2 minting has not started yet");
    require(block.timestamp <= phase2ClosingTimestamp, "Phase 2 minting has ended");
        require(phase2ReservedMinted + _numLostSouls <= 510, "Exceeded Phase 2 reserve supply");
        require(_lilHottiesTokenIds.length % 2 == 0, "You must provide 2 Lil Hotties token IDs for each Lost Soul to mint.");
        require(_lilHottiesTokenIds.length / 2 == _numLostSouls, "Mismatch in the number of tokens and Lost Souls to mint.");
        require(totalSupply() + _numLostSouls <= MAX_MINT, "Exceeded maximum supply");

        // Check if Lil Hotties token IDs have already been redeemed in Phase 2
        for (uint256 i = 0; i < _lilHottiesTokenIds.length; i++) {
            require(phaseTokenIds[Phase.PHASE2][_lilHottiesTokenIds[i]], "Invalid Lil Hotties token for Phase 2");
            require(!phase2RedeemedTokenIds[_lilHottiesTokenIds[i]], "This token ID has already been redeemed in Phase 2.");
        }

        // Phase 2 minting logic
        for (uint256 i = 0; i < _lilHottiesTokenIds.length; i += 2) {
            _mintLostSoul(_lilHottiesTokenIds[i], i);
        }
    }

// Phase 3 Minting Requirements
else if (mintPhase == uint8(Phase.PHASE3)) {
    require(block.timestamp >= phase3Timestamp, "Phase 3 minting has not started yet");
    require(block.timestamp <= phase3ClosingTimestamp, "Phase 3 minting has ended");
        require(_lilHottiesTokenIds.length % 3 == 0, "You must provide 3 Lil Hotties token IDs for each Lost Soul to mint.");
        require(_lilHottiesTokenIds.length / 3 == _numLostSouls, "Mismatch in the number of tokens and Lost Souls to mint.");
        require(totalSupply() + _numLostSouls <= MAX_MINT, "Exceeded maximum supply");
        require(phase3And4Minted + _numLostSouls <= 891, "Exceeded Phase 3 and 4 supply limit");

        // Check if Lil Hotties token IDs have already been redeemed in Phase 3
        for (uint256 i = 0; i < _lilHottiesTokenIds.length; i++) {
            require(phaseTokenIds[Phase.PHASE3][_lilHottiesTokenIds[i]], "Invalid Lil Hotties token for Phase 3");
            require(!phase3RedeemedTokenIds[_lilHottiesTokenIds[i]], "This token ID has already been redeemed in Phase 3.");
        }
        // Phase 3 minting logic
        for (uint256 j = 0; j < _lilHottiesTokenIds.length; j += 3) {
            _mintLostSoul(_lilHottiesTokenIds[j], j);
            phase3And4Minted += 1; // Update the counter for Phase 3 and 4 minted tokens
        }
    }

// Phase 4 Minting Requirements
else if (mintPhase == uint8(Phase.PHASE4)) {
    require(block.timestamp >= phase4Timestamp, "Phase 4 minting has not started yet");
    require(block.timestamp <= phase4ClosingTimestamp, "Phase 4 minting has ended");
    require(totalSupply() + _numLostSouls <= MAX_MINT, "Exceeded maximum supply");

    // Mint from Phase 4 public supply by default
    bool mintFromPublicSupply = true;

    // Check if the 891-token limit for Phase 3 and Phase 4 is reached
    if (phase3And4Minted + _numLostSouls > 891) {
        // Check if the reserve supply is released
        if (reservedSupplyReleased) {
            // Mint from Phase 1 or Phase 2 reserve supply if available
            if (phase1ReservedSupply + phase2ReservedSupply > 0) {
                // Mint from Phase 1 reserve supply if available
                if (phase1ReservedSupply > 0) {
                    require(phase1ReservedMinted + _numLostSouls <= 99, "Exceeded Phase 1 reserve supply");
                    for (uint256 i = 0; i < _numLostSouls; i++) {
                        _mintLostSoul(0, i); // Pass 0 as the Lil Hotties token ID for Phase 1
                        phase1ReservedSupply -= 1;
                        phase1ReservedMinted += 1;
                    }
                    mintFromPublicSupply = false;
                }

                // Mint from Phase 2 reserve supply if available
                if (mintFromPublicSupply && phase2ReservedSupply > 0) {
                    require(phase2ReservedMinted + _numLostSouls <= 510, "Exceeded Phase 2 reserve supply");
                    for (uint256 i = 0; i < _numLostSouls; i++) {
                        _mintLostSoul(0, i); // Pass 0 as the Lil Hotties token ID for Phase 2
                        phase2ReservedSupply -= 1;
                        phase2ReservedMinted += 1;
                    }
                    mintFromPublicSupply = false;
                }
            }
        }
    }

    // Mint from Phase 4 public supply if not minted from reserves
    if (mintFromPublicSupply) {
        require(phase3And4Minted + _numLostSouls <= 891, "Exceeded phase 3 and 4 minting limit");
        for (uint256 i = 0; i < _numLostSouls; i++) {
            uint256 salt = i;
            _mintLostSoul(0, salt); // Pass 0 as the Lil Hotties token ID for Phase 4
            phase3And4Minted += 1;
        }
    }
        }
    }
    // Function to check the remaining reserved supply
    function reservedSupplyRemaining() public view returns (uint256) {
        return phase1ReservedSupply + phase2ReservedSupply;
    }

function _mintLostSoul(uint256 _lilHottiesTokenId, uint256 salt) internal {
    require(totalSupply() < MAX_MINT, "Exceeded maximum supply");

    uint256 artworkIndex = _getRandomArtworkIndex(salt);
    while (artworks[artworkIndex].currentSupply >= artworks[artworkIndex].maxSupply) {
        artworkIndex = (artworkIndex + 1) % artworks.length;
    }
    artworks[artworkIndex].currentSupply += 1;

    // Phase 1 Minting
    if (currentPhase == Phase.PHASE1) {
require(phase1ReservedSupply > 0 && block.timestamp <= phase1ClosingTimestamp, "Phase 1 minting is closed");
        require(phaseTokenIds[Phase.PHASE1][_lilHottiesTokenId], "Invalid Lil Hotties token for Phase 1");
        require(!phase1RedeemedTokenIds[_lilHottiesTokenId], "This token ID has already been redeemed in Phase 1.");
        phase1RedeemedTokenIds[_lilHottiesTokenId] = true;
        phase1ReservedSupply -= 1;
        phase1ReservedMinted += 1;
    }
    // Phase 2 Minting
    else if (currentPhase == Phase.PHASE2) {
require(phase2ReservedSupply > 0 && block.timestamp <= phase2ClosingTimestamp, "Phase 2 minting is closed");
        require(phaseTokenIds[Phase.PHASE2][_lilHottiesTokenId], "Invalid Lil Hotties token for Phase 2");
        require(!phase2RedeemedTokenIds[_lilHottiesTokenId], "This token ID has already been redeemed in Phase 2.");
        phase2RedeemedTokenIds[_lilHottiesTokenId] = true;
        phase2ReservedSupply -= 1;
        phase2ReservedMinted += 1;
    }
    // Phase 3 Minting
    else if (currentPhase == Phase.PHASE3) {
        require(phaseTokenIds[Phase.PHASE3][_lilHottiesTokenId], "Invalid Lil Hotties token for Phase 3");
        require(!phase3RedeemedTokenIds[_lilHottiesTokenId], "This token ID has already been redeemed in Phase 3.");
        phase3RedeemedTokenIds[_lilHottiesTokenId] = true;
        require(phase3And4Minted + 1 <= 891, "Exceeded phase 3 and 4 minting limit");
    }
    // Phase 4 Minting
    else if (currentPhase == Phase.PHASE4) {
        require(reservedSupplyReleased, "Reserved supply cannot be minted until it is released by the owner");
        require(phase3And4Minted + 1 <= 891, "Exceeded phase 3 and 4 minting limit");
    }

    uint256 mintIndex = totalSupply() + 1;
    _mint(msg.sender, mintIndex);
    _tokenURIs[mintIndex] = artworks[artworkIndex].uri;
}

    function initializeArtworks() external onlyAdmin {
        require(artworks.length == 0, "Artworks array is already initialized");

        artworks.push(Artwork("https://ipfs.io/ipfs/Qmf88thaVJNoYPYjJyRTWE5EuT7M7w4QUSpxb4Zv61bMvy", 280, 0));
        artworks.push(Artwork("https://ipfs.io/ipfs/QmPU4ZMFmPnDqQPFcJETLDC9ubRyGwcaUaybmx8sHh68Ww", 100, 0));
        artworks.push(Artwork("https://ipfs.io/ipfs/Qmf5VhNNcHSyTDpH6sQzyo6e4fMTyVYb6VLUcUijUd84VF", 230, 0));
        artworks.push(Artwork("https://ipfs.io/ipfs/Qmb31d57jYqP946TAsk6xxaA8mMFifokhQbfeCSxRPCW2L", 140, 0));
        artworks.push(Artwork("https://ipfs.io/ipfs/Qme5E97MTq1LRK2C71nEUwpZJ7TcBG5pva9WMdD5N7cGXW", 200, 0));
        artworks.push(Artwork("https://ipfs.io/ipfs/Qme4jXSk73JTy47PqNnQk3Kt6yL1kALjEniNn3mweAqKFe", 550, 0));
        artworks.push(Artwork("https://ipfs.io/ipfs/QmVp9wfvPd5M9KkBoe6JyfTScbPh3Lq2EZg5brqqzUvQWn", 330, 0));
        artworks.push(Artwork("https://ipfs.io/ipfs/QmUhqoa7aBtVdHr7f7brV11DFM6UuBo7LumtEQRb5huStb", 460, 0));
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_exists(tokenId), "ERC721Metadata: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    // Function to release the reserved supply
    function releaseReservedSupply() external onlyAdmin {
        require(!reservedSupplyReleased, "Reserved supply has already been released");
        require(block.timestamp >= phase2ClosingTimestamp, "Cannot release reserved supply before Phase 2 Reserve Ending");

        reservedSupplyReleased = true;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(tokenId > 0 && tokenId <= totalSupply(), "URI query for nonexistent token");
        return _tokenURIs[tokenId];
    }

    // Function to withdraw Ether from the contract
    function withdrawEther() external onlyAdmin {
        uint256 balance = address(this).balance;
        require(balance > 0, "No Ether to withdraw");
        payable(owner()).transfer(balance);
    }

    // Function to set the royalty percentage
    function setRoyaltyPercentage(uint256 _percentage) external onlyAdmin {
        require(_percentage <= 100, "Royalty percentage cannot exceed 100%");
        _royaltyPercentage = _percentage;
    }

    // Function to set the royalty receiver address
    function setRoyaltyReceiver(address _receiver) external onlyAdmin {
        require(_receiver != address(0), "Invalid address");
        _royaltyReceiver = _receiver;
    }

    // Function to get the royalty percentage
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view override returns (address, uint256) {
        require(tokenId > 0 && tokenId <= totalSupply(), "Invalid token ID");
        uint256 royaltyAmount = (salePrice * _royaltyPercentage) / 100;
        return (_royaltyReceiver, royaltyAmount);
    }
}