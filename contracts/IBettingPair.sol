// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface IBettingPair {
    enum CHOICE { WIN, DRAW, LOSE }
    enum BETSTATUS { BETTING, REVIEWING, CLAIMING }
    enum TOKENTYPE { ETH, WCI }
    enum LPTOKENTYPE { ETH, USDT, USDC, SHIB, DOGE }

    function bet(address, uint256, uint256, CHOICE, TOKENTYPE, uint256, uint256, uint256, uint256, uint256) external;
    function claim(address, TOKENTYPE) external returns (uint256[] memory);

    function calcEarning(address, TOKENTYPE) external view returns (uint256[] memory);
    function calcMultiplier(TOKENTYPE) external view returns (uint256[] memory);

    function getPlayerBetAmount(address, TOKENTYPE) external view returns (uint256[] memory);
    function getPlayerClaimHistory(address, TOKENTYPE) external view returns (uint256);

    function getBetResult() external view returns (CHOICE);
    function setBetResult(CHOICE _result) external;

    function getBetStatus() external view returns (BETSTATUS);
    function setBetStatus(BETSTATUS _status) external;

    function getTotalBet(TOKENTYPE) external view returns (uint256);
    function getTotalBetPerChoice(TOKENTYPE) external view returns (uint256[] memory);

    function getWciTokenThreshold() external view returns (uint256);
    function setWciTokenThreshold(uint256) external;

    function getLockPool(address) external view returns (uint256[] memory);
}