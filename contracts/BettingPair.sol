// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./IBettingPair.sol";
import "./SafeMath.sol";
import "./IERC20.sol";

/*
* @This contract actually doesn't manage token and coin transfer.
* @It is responsible for only amount management.
*/

contract BettingPair is Ownable, IBettingPair {
    using SafeMath for uint256;

    mapping(address => mapping(TOKENTYPE => mapping(CHOICE => uint256))) players;
    mapping(address => mapping(TOKENTYPE => mapping(CHOICE => uint256))) originalBets;
    mapping(address => mapping(TOKENTYPE => mapping(CHOICE => uint256))) betHistory;
    mapping(address => mapping(TOKENTYPE => uint256)) claimHistory;
    CHOICE betResult;
    BETSTATUS betStatus = BETSTATUS.BETTING;

    mapping(TOKENTYPE => uint256) totalBet;
    mapping(TOKENTYPE => mapping(CHOICE => uint256)) totalBetPerChoice;

    IERC20 public wciToken = IERC20(0xC5a9BC46A7dbe1c6dE493E84A18f02E70E2c5A32);
    uint256 wciTokenThreshold = 50000 * 10**9; // 50,000 WCI as a threshold.

    mapping(address => mapping(LPTOKENTYPE => mapping(CHOICE => uint256))) _lockPool;

    constructor() {}

    /*
    * @Function to bet (Main function).
    * @params:
    *   _player: user wallet address
    *   _amount: bet amount
    *   _choice: bet choice (3 choices - First team wins, draws and loses)
    *   _token: Users can bet using ETH or WCI
    *   When there is a multiplier(x2 or x3) in bet, there should be some amounts of collateral tokens
    *   (ETH, USDT, USDC, SHIB, DOGE) in leverage pool. The rest parameters are the amounts for _amount*(multiplier-1) ether.
    */
    function bet(address _player, uint256 _amount, uint256 _multiplier, CHOICE _choice, TOKENTYPE _token,
        uint256 ethCol, uint256 usdtCol, uint256 usdcCol, uint256 shibCol, uint256 dogeCol)
        external
        override
        onlyOwner 
    {
        require(betStatus == BETSTATUS.BETTING, "You can not bet at this time.");
        uint256 realBet = _amount.mul(_multiplier);
        totalBet[_token] += realBet;
        totalBetPerChoice[_token][_choice] += realBet;
        players[_player][_token][_choice] += realBet;
        originalBets[_player][_token][_choice] += _amount;
        betHistory[_player][_token][_choice] += realBet;

        _lockPool[_player][LPTOKENTYPE.ETH][_choice] += ethCol;
        _lockPool[_player][LPTOKENTYPE.USDT][_choice] += usdtCol;
        _lockPool[_player][LPTOKENTYPE.USDC][_choice] += usdcCol;
        _lockPool[_player][LPTOKENTYPE.SHIB][_choice] += shibCol;
        _lockPool[_player][LPTOKENTYPE.DOGE][_choice] += dogeCol;
    }

    /*
    * @Function to claim earnings from bet.
    * @It returns how many ether or WCI user will earn from bet.
    */
    function claim(address _player, TOKENTYPE _token) external override onlyOwner returns (uint256[] memory) {
        require(betStatus == BETSTATUS.CLAIMING, "You can not claim at this time.");
        require(players[_player][_token][betResult] > 0, "You don't have any earnings to withdraw.");

        uint256[] memory res = calculateEarning(_player, betResult, _token);
        claimHistory[_player][_token] = res[0];
        players[_player][_token][CHOICE.WIN] = 0;
        players[_player][_token][CHOICE.DRAW] = 0;
        players[_player][_token][CHOICE.LOSE] = 0;
        originalBets[_player][_token][CHOICE.WIN] = 0;
        originalBets[_player][_token][CHOICE.DRAW] = 0;
        originalBets[_player][_token][CHOICE.LOSE] = 0;

        return res;
    }

    /*
    * @returns an array of 7 elements. The first element is user's winning amount and the second element is
    *   site owner's profit which will be transferred to tax collector wallet. The remaining amounts are collateral
    *   token amounts.
    */
    function calculateEarning(address _player, CHOICE _choice, TOKENTYPE _token) internal view returns (uint256[] memory) {
        uint256[] memory res = new uint256[](7);

        uint256 userBal = originalBets[_player][_token][_choice];
        uint256 realBal = players[_player][_token][_choice];

        // If there are no opponent bets, the player will claim his original bet amount.
        if (totalBetPerChoice[_token][CHOICE.WIN] == 0 && totalBetPerChoice[_token][CHOICE.DRAW] == 0) {
            res[0] = originalBets[_player][_token][CHOICE.LOSE];
            res[2] = _lockPool[_player][LPTOKENTYPE.ETH][CHOICE.LOSE];
            res[3] = _lockPool[_player][LPTOKENTYPE.USDT][CHOICE.LOSE];
            res[4] = _lockPool[_player][LPTOKENTYPE.USDC][CHOICE.LOSE];
            res[5] = _lockPool[_player][LPTOKENTYPE.SHIB][CHOICE.LOSE];
            res[6] = _lockPool[_player][LPTOKENTYPE.DOGE][CHOICE.LOSE];
            return res;
        } else if (totalBetPerChoice[_token][CHOICE.WIN] == 0 && totalBetPerChoice[_token][CHOICE.LOSE] == 0) {
            res[0] = originalBets[_player][_token][CHOICE.DRAW];
            res[2] = _lockPool[_player][LPTOKENTYPE.ETH][CHOICE.DRAW];
            res[3] = _lockPool[_player][LPTOKENTYPE.USDT][CHOICE.DRAW];
            res[4] = _lockPool[_player][LPTOKENTYPE.USDC][CHOICE.DRAW];
            res[5] = _lockPool[_player][LPTOKENTYPE.SHIB][CHOICE.DRAW];
            res[6] = _lockPool[_player][LPTOKENTYPE.DOGE][CHOICE.DRAW];
            return res;
        } else if (totalBetPerChoice[_token][CHOICE.DRAW] == 0 && totalBetPerChoice[_token][CHOICE.LOSE] == 0) {
            res[0] = originalBets[_player][_token][CHOICE.WIN];
            res[2] = _lockPool[_player][LPTOKENTYPE.ETH][CHOICE.WIN];
            res[3] = _lockPool[_player][LPTOKENTYPE.USDT][CHOICE.WIN];
            res[4] = _lockPool[_player][LPTOKENTYPE.USDC][CHOICE.WIN];
            res[5] = _lockPool[_player][LPTOKENTYPE.SHIB][CHOICE.WIN];
            res[6] = _lockPool[_player][LPTOKENTYPE.DOGE][CHOICE.WIN];
            return res;
        } else if (totalBetPerChoice[_token][_choice] == 0) {
            return res;
        }

        uint256 _wciTokenBal = wciToken.balanceOf(_player);

        // If the token is ETH, the player will take 5% tax if he holds enough WCI token. Otherwise he will take 10% tax.
        if (_token == TOKENTYPE.ETH) {
            if (_wciTokenBal >= wciTokenThreshold) {
                res[0] = userBal + realBal.mul(totalBet[_token]-totalBetPerChoice[_token][_choice]).mul(19).div(20).div(totalBetPerChoice[_token][_choice]);
                res[1] = realBal.mul(totalBet[_token]-totalBetPerChoice[_token][_choice]).div(20).div(totalBetPerChoice[_token][_choice]);
            } else {
                res[0] = userBal + realBal.mul(totalBet[_token]-totalBetPerChoice[_token][_choice]).mul(9).div(10).div(totalBetPerChoice[_token][_choice]);
                res[1] = realBal.mul(totalBet[_token]-totalBetPerChoice[_token][_choice]).div(10).div(totalBetPerChoice[_token][_choice]);
            }
            res[2] = _lockPool[_player][LPTOKENTYPE.ETH][_choice];
            res[3] = _lockPool[_player][LPTOKENTYPE.USDT][_choice];
            res[4] = _lockPool[_player][LPTOKENTYPE.USDC][_choice];
            res[5] = _lockPool[_player][LPTOKENTYPE.SHIB][_choice];
            res[6] = _lockPool[_player][LPTOKENTYPE.DOGE][_choice];
        }
        // If the token is WCI, there is no tax.
        else if (_token == TOKENTYPE.WCI) {
            res[0] = totalBet[_token].mul(userBal).div(totalBetPerChoice[_token][_choice]);
        }

        return res;
    }

    /*
    * @Function to calculate earning for given player and token.
    */
    function calcEarning(address _player, TOKENTYPE _token) external override view onlyOwner returns (uint256[] memory) {
        uint256[] memory res = new uint256[](3);
        res[0] = calculateEarning(_player, CHOICE.WIN, _token)[0];
        res[1] = calculateEarning(_player, CHOICE.DRAW, _token)[0];
        res[2] = calculateEarning(_player, CHOICE.LOSE, _token)[0];
        return res;
    }

    // Calculate how many times reward will player take. It uses 10% tax formula to give users the approximate multiplier before bet.
    function calculateMultiplier(CHOICE _choice, IBettingPair.TOKENTYPE _token) internal view returns (uint256) {
        if (_token == IBettingPair.TOKENTYPE.ETH) {
            if (totalBetPerChoice[_token][_choice] == 0) {
                return 1000;
            } else {
                return totalBet[_token].mul(900).div(totalBetPerChoice[_token][_choice]) + 100;       
            }
        } else {
            if (totalBetPerChoice[_token][_choice] == 0) {
                return 950;
            } else {
                return totalBet[_token].mul(1000).div(totalBetPerChoice[_token][_choice]);
            }
        }
    }

    /*
    * @Function to calculate multiplier.
    */
    function calcMultiplier(IBettingPair.TOKENTYPE _token) external override view onlyOwner returns (uint256[] memory) {
        uint256[] memory res = new uint256[](3);
        res[0] = calculateMultiplier(CHOICE.WIN, _token);
        res[1] = calculateMultiplier(CHOICE.DRAW, _token);
        res[2] = calculateMultiplier(CHOICE.LOSE, _token);
        return res;
    }

    /*
    * @Function to get player bet amount.
    * @It uses betHistory variable because players variable is initialized to zero if user claims.
    */
    function getPlayerBetAmount(address _player, TOKENTYPE _token) external override view onlyOwner returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](3);
        arr[0] = betHistory[_player][_token][CHOICE.WIN];
        arr[1] = betHistory[_player][_token][CHOICE.DRAW];
        arr[2] = betHistory[_player][_token][CHOICE.LOSE];

        return arr;
    }

    /*
    * @Function to get player claim history.
    */
    function getPlayerClaimHistory(address _player, TOKENTYPE _token) external override view onlyOwner returns (uint256) {
        return claimHistory[_player][_token];
    }

    /*
    * @Function to get bet result.
    */
    function getBetResult() external view override onlyOwner returns (CHOICE) {
        return betResult;
    }

    /*
    * @Function to set the bet result.
    */
    function setBetResult(CHOICE _result) external override onlyOwner {
        betResult = _result;
        betStatus = BETSTATUS.CLAIMING;
    }

    /*
    * @Function to get bet status.
    */
    function getBetStatus() external view override onlyOwner returns (BETSTATUS) {
        return betStatus;
    }

    /*
    * @Function to set bet status.
    */
    function setBetStatus(BETSTATUS _status) external override onlyOwner {
        betStatus = _status;
    }

    /*
    * @Function to get total bet amount.
    */
    function getTotalBet(TOKENTYPE _token) external view override onlyOwner returns (uint256) {
        return totalBet[_token];
    }

    /*
    * @Function to get total bet amounts per choice.
    * @There are 3 choices(WIN, DRAW, LOSE) so it returns an array of 3 elements.
    */
    function getTotalBetPerChoice(TOKENTYPE _token) external view override onlyOwner returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](3);
        arr[0] = totalBetPerChoice[_token][CHOICE.WIN];
        arr[1] = totalBetPerChoice[_token][CHOICE.DRAW];
        arr[2] = totalBetPerChoice[_token][CHOICE.LOSE];

        return arr;
    }

    /*
    * @Function to get WCI token threshold.
    */
    function getWciTokenThreshold() external view override onlyOwner returns (uint256) {
        return wciTokenThreshold;
    }

    /*
    * @Function to set WCI token threshold.
    */
    function setWciTokenThreshold(uint256 _threshold) external override onlyOwner {
        wciTokenThreshold = _threshold;
    }

    /*
    * @Function to get lock pool information.
    */
    function getLockPool(address player) external view override returns (uint256[] memory) {
        uint256[] memory res = new uint256[](15);

        res[0] = _lockPool[player][LPTOKENTYPE.ETH][CHOICE.WIN];
        res[1] = _lockPool[player][LPTOKENTYPE.USDT][CHOICE.WIN];
        res[2] = _lockPool[player][LPTOKENTYPE.USDC][CHOICE.WIN];
        res[3] = _lockPool[player][LPTOKENTYPE.SHIB][CHOICE.WIN];
        res[4] = _lockPool[player][LPTOKENTYPE.DOGE][CHOICE.WIN];

        res[5] = _lockPool[player][LPTOKENTYPE.ETH][CHOICE.DRAW];
        res[6] = _lockPool[player][LPTOKENTYPE.USDT][CHOICE.DRAW];
        res[7] = _lockPool[player][LPTOKENTYPE.USDC][CHOICE.DRAW];
        res[8] = _lockPool[player][LPTOKENTYPE.SHIB][CHOICE.DRAW];
        res[9] = _lockPool[player][LPTOKENTYPE.DOGE][CHOICE.DRAW];

        res[10] = _lockPool[player][LPTOKENTYPE.ETH][CHOICE.LOSE];
        res[11] = _lockPool[player][LPTOKENTYPE.USDT][CHOICE.LOSE];
        res[12] = _lockPool[player][LPTOKENTYPE.USDC][CHOICE.LOSE];
        res[13] = _lockPool[player][LPTOKENTYPE.SHIB][CHOICE.LOSE];
        res[14] = _lockPool[player][LPTOKENTYPE.DOGE][CHOICE.LOSE];

        return res;
    }
}