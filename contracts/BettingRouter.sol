// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./Counters.sol";
import "./BettingPair.sol";
import "./IUniswapV2Pair.sol";
import "./LeveragePool.sol";

contract BettingRouter is Ownable {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    mapping (uint256 => address) pairs; // All pair contract addresses
    Counters.Counter matchId;           // variable for managing match id
    address taxCollectorAddress = 0x41076e8DEbC1C51E0225CF73Cc23Ebd9D20424CE;        // Tax collector address
    mapping(IBettingPair.TOKENTYPE => uint256) totalClaim;          // Total user claim amount
    mapping(IBettingPair.TOKENTYPE => uint256) totalWinnerCount;    // Total winner count

    IERC20 wciToken = IERC20(0xC5a9BC46A7dbe1c6dE493E84A18f02E70E2c5A32);
    IERC20USDT _usdt = IERC20USDT(0xdAC17F958D2ee523a2206206994597C13D831ec7);  // USDT token
    IERC20 _usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);          // USDC token
    IERC20 _shib = IERC20(0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE);          // SHIB token
    IERC20 _doge = IERC20(0x4206931337dc273a630d328dA6441786BfaD668f);          // DOGE token

    LeveragePool public _lpPool;

    // Events
    // event Bet(uint256 pairId, address player, uint256 amount, IBettingPair.CHOICE choice, IBettingPair.TOKENTYPE token,
    //     uint256 multiplier, uint256 ethCol, uint256 usdtCol, uint256 usdcCol, uint256 shibCol, uint256 dogeCol);
    // event Claim(uint256 pairId, address player, uint256 amount, IBettingPair.CHOICE choice, IBettingPair.TOKENTYPE);
    // event CreatePair(uint256 pairId, address pairAddress);
    // event SetBetResult(uint256 pairId, IBettingPair.CHOICE result);
    // event SetBetStatus(uint256 pairId, IBettingPair.BETSTATUS status);
    // event WithdrawFromRouter(uint256 amount, IBettingPair.TOKENTYPE token);

    // event DepositCollateral(IBettingPair.LPTOKENTYPE token, uint256 amount);
    // event WithdrawCollateral(IBettingPair.LPTOKENTYPE token, uint256 amount);

    constructor() {
        _lpPool = new LeveragePool();
    }

    /*
    * @Check if the input pair id is valid
    */
    modifier onlyValidPair(uint256 _id) {
        require(_id >= 0, "Pair id should not be negative.");
        require(_id < matchId.current(), "Invalid pair id.");
        _;
    }

    /*
    * @Check if the amount condition meets per token
    */
    modifier betConditions(uint _amount, IBettingPair.TOKENTYPE _token) {
        if (_token == IBettingPair.TOKENTYPE.ETH) {
            require(_amount >= 0.01 ether, "Insuffisant amount, please increase your bet!");
        } else if (_token == IBettingPair.TOKENTYPE.WCI) {
            require(_amount >= 1000 gwei, "Insuffisant amount, please increase your bet!");
        }
        _;
    }

    /*
    * @Function to create one pair for a match
    */
    function createOne() public onlyOwner {
        BettingPair _pair = new BettingPair();
        pairs[matchId.current()] = address(_pair);
        matchId.increment();
    }

    /*
    * Function for betting with ethers.
    * This function should be separated from other betting function because this is payable function.
    */
    function betEther(uint256 _pairId, IBettingPair.CHOICE _choice, uint256 _multiplier) external payable
        onlyValidPair(_pairId)
        betConditions(msg.value, IBettingPair.TOKENTYPE.ETH)
    {
        uint256 ethInLPPool = _lpPool.getPlayerLPBalanceInEth(msg.sender);
        require(ethInLPPool >= (msg.value).mul(_multiplier.sub(1)), "You don't have enough collaterals for that mulbiplier.");

        uint256 ethCol;     // ETH collateral amount
        uint256 usdtCol;    // USDT collateral amount
        uint256 usdcCol;    // USDC collateral amount
        uint256 shibCol;    // SHIB collateral amount
        uint256 dogeCol;    // DOGE collateral amount

        (ethCol, usdtCol, usdcCol, shibCol, dogeCol) = _lpPool.calcLockTokenAmountsAsCollateral(msg.sender, (msg.value).mul(_multiplier.sub(1)));
        _lpPool.lock(msg.sender, ethCol, usdtCol, usdcCol, shibCol, dogeCol);
        _lpPool.unlock(owner(), ethCol, usdtCol, usdcCol, shibCol, dogeCol);

        IBettingPair(pairs[_pairId]).bet(msg.sender, (msg.value).mul(_multiplier), _choice, IBettingPair.TOKENTYPE.ETH,
            ethCol, usdtCol, usdcCol, shibCol, dogeCol);
        // emit Bet(_pairId, msg.sender, msg.value, _choice, IBettingPair.TOKENTYPE.ETH, _multiplier, ethCol, usdtCol, usdcCol, shibCol, dogeCol);
    }

    /*
    * Function for betting with WCI.
    * This function should be separated from ETH and other tokens because this token's transferFrom function has default tax rate.
    */
    function betWCI(uint256 _pairId, uint256 _betAmount, IBettingPair.CHOICE _choice) external
        onlyValidPair(_pairId)
        betConditions(_betAmount, IBettingPair.TOKENTYPE.WCI)
    {
        // uint256 wciBalance = wciToken.balanceOf(msg.sender);
        // require(wciBalance >= _betAmount, "User doesn't have enough balance");
        wciToken.transferFrom(msg.sender, address(this), _betAmount);

        // Apply 5% tax to all bet amounts.
        IBettingPair(pairs[_pairId]).bet(msg.sender, _betAmount.mul(19).div(20), _choice, IBettingPair.TOKENTYPE.WCI, 0, 0, 0, 0, 0);
        // emit Bet(_pairId, msg.sender, _betAmount, _choice, IBettingPair.TOKENTYPE.WCI, 1, 0, 0, 0, 0, 0);
    }

    /*
    * @Function to claim earnings.
    */
    function claim(uint256 _pairId, IBettingPair.TOKENTYPE _token) external onlyValidPair(_pairId) {
        uint256[] memory claimInfo = IBettingPair(pairs[_pairId]).claim(msg.sender, _token);
        uint256 _amountClaim = claimInfo[0];
        uint256 _amountTax = claimInfo[1];
        require(_amountClaim > 0, "You do not have any profit in this bet");

        if (_token == IBettingPair.TOKENTYPE.ETH) {
            payable(msg.sender).transfer(_amountClaim);
            payable(taxCollectorAddress).transfer(_amountTax);

            _lpPool.unlock(msg.sender, claimInfo[2], claimInfo[3], claimInfo[4], claimInfo[5], claimInfo[6]);
            _lpPool.lock(msg.sender, claimInfo[2], claimInfo[3], claimInfo[4], claimInfo[5], claimInfo[6]);
        } else if (_token == IBettingPair.TOKENTYPE.WCI) {
            wciToken.transfer(msg.sender, _amountClaim);
        }
        
        totalWinnerCount[_token] ++;
        totalClaim[_token] += _amountClaim;
        // emit Claim(_pairId, msg.sender, _amountClaim, IBettingPair(pairs[_pairId]).getBetResult(), _token);
    }

    /*
    * @Function to withdraw tokens from router contract.
    */
    function withdrawPFromRouter(uint256 _amount, IBettingPair.TOKENTYPE _token) external doubleChecker {
        require(_amount > 0, "Amount should be bigger than 0");
        if (_token == IBettingPair.TOKENTYPE.ETH) {
            // require(_amount <= address(this).balance, "Exceed the contract balance");
            payable(owner()).transfer(_amount);
        } else if (_token == IBettingPair.TOKENTYPE.WCI) {
            // uint256 wciBalance = wciToken.balanceOf(address(this));
            // require(_amount <= wciBalance, "Exceed the contract WCI balance");
            wciToken.transfer(owner(), _amount);
        }
        
        // emit WithdrawFromRouter(_amount, _token);
    }

    /*
    * @Function to get player bet amount per token.
    */
    function _getPlayerBetAmount(address _player, IBettingPair.TOKENTYPE _token) internal view returns (uint256[] memory) {
        uint256[] memory res = new uint256[](matchId.current() * 3);

        for (uint256 i=0; i<matchId.current(); i++) {
            uint256[] memory temp = IBettingPair(pairs[i]).getPlayerBetAmount(_player, _token);
            res[i*3] = temp[0];
            res[i*3 + 1] = temp[1];
            res[i*3 + 2] = temp[2];
        }
        
        return res;
    }

    /*
    * @Function to get player bet amounts for all tokens.
    */
    function getPlayerBetAmount(address _player) external view returns (uint256[] memory, uint256[] memory) {
        return (
            _getPlayerBetAmount(_player, IBettingPair.TOKENTYPE.ETH),
            _getPlayerBetAmount(_player, IBettingPair.TOKENTYPE.WCI)
        );
    }

    /*
    * @Function to get multiplier per token.
    */
    function _getMultiplier(IBettingPair.TOKENTYPE _token) internal view returns (uint256[] memory) {
        uint256[] memory res = new uint256[](matchId.current() * 3);
        
        for (uint256 i=0; i<matchId.current(); i++) {
            uint256[] memory pairRes = IBettingPair(pairs[i]).calcMultiplier(_token);
            res[i*3] = pairRes[0];
            res[i*3+1] = pairRes[1];
            res[i*3+2] = pairRes[2];
        }

        return res;
    }

    /*
    * @Function to get multipliers for all tokens.
    */
    function getMultiplier() external view returns (uint256[] memory, uint256[] memory) {
        return (
            _getMultiplier(IBettingPair.TOKENTYPE.ETH),
            _getMultiplier(IBettingPair.TOKENTYPE.WCI)
        );
    }

    /*
    * @Function to get player claim history per token.
    * @Once the user claim, the player balance will be 0 and we can't get user bet information anymore.
    * @This function is used to get user claim history.
    */
    function _getPlayerClaimHistory(address _player, IBettingPair.TOKENTYPE _token) internal view returns (uint256[] memory) {
        uint256[] memory res = new uint256[](matchId.current());

        for (uint256 i=0; i<matchId.current(); i++) {
            res[i] = IBettingPair(pairs[i]).getPlayerClaimHistory(_player, _token);
        }

        return res;
    }

    /*
    * @Function to get player claim history for all tokens.
    */
    function getPlayerClaimHistory(address _player) external view returns (uint256[] memory, uint256[] memory) {
        return (
            _getPlayerClaimHistory(_player, IBettingPair.TOKENTYPE.ETH),
            _getPlayerClaimHistory(_player, IBettingPair.TOKENTYPE.WCI)
        );
    }

    /*
    * @Function to get pair information per token.
    * @You can get match result, match status, total bet, total bets per choice per token.
    */
    // function _getPairInformation(uint256 _pairId, IBettingPair.TOKENTYPE _token) internal view onlyValidPair(_pairId) returns (uint256[] memory) {
    //     uint256[] memory res = new uint256[](6);
    //     res[0] = uint256(IBettingPair(pairs[_pairId]).getBetResult());
    //     res[1] = uint256(IBettingPair(pairs[_pairId]).getBetStatus());
    //     res[2] = IBettingPair(pairs[_pairId]).getTotalBet(_token);

    //     uint256[] memory _choiceBetAmount = IBettingPair(pairs[_pairId]).getTotalBetPerChoice(_token);
    //     res[3] = _choiceBetAmount[0];
    //     res[4] = _choiceBetAmount[1];
    //     res[5] = _choiceBetAmount[2];

    //     return res;
    // }

    /*
    * @Function to get pair information for all tokens.
    */
    // function getPairInformation(uint256 _pairId) external view onlyValidPair(_pairId) returns (uint256[] memory, uint256[] memory) {
    //     return (
    //         _getPairInformation(_pairId, IBettingPair.TOKENTYPE.ETH),
    //         _getPairInformation(_pairId, IBettingPair.TOKENTYPE.WCI)
    //     );
    // }

    /*
    * @Function to get the newly creating match id.
    */
    function getMatchId() external view returns (uint256) {
        return matchId.current();
    }

    /*
    * @Function to get user earning amounts per match.
    * @This function is used to get how much earning user has to claim.
    */
    function _getClaimAmount(IBettingPair.TOKENTYPE _token) internal view returns (uint256[] memory) {
        uint256[] memory res = new uint256[](matchId.current() * 3);
        
        for (uint256 i=0; i<matchId.current(); i++) {
            uint256[] memory pairRes = IBettingPair(pairs[i]).calcEarning(msg.sender, _token);
            res[i*3] = pairRes[0];
            res[i*3+1] = pairRes[1];
            res[i*3+2] = pairRes[2];
        }

        return res;
    }

    /*
    * @Function to get user earning amounts for all matches.
    */
    function getClaimAmount() external view returns (uint256[] memory, uint256[] memory) {
        return (
            _getClaimAmount(IBettingPair.TOKENTYPE.ETH),
            _getClaimAmount(IBettingPair.TOKENTYPE.WCI)
        );
    }

    /*
    * @Function to get match status for all matches.
    */
    function getBetStatus() external view returns (IBettingPair.BETSTATUS[] memory) {
        IBettingPair.BETSTATUS[] memory res = new IBettingPair.BETSTATUS[](matchId.current());

        for (uint256 i=0; i<matchId.current(); i++) {
            res[i] = IBettingPair(pairs[i]).getBetStatus();
        }

        return res;
    }

    /*
    * @Function to get match result for all matches.
    * @The default value is CHOICE.WIN(0) and the value from this result is valid only if the match status is CLAIMING(2).
    */
    function getBetResult() external view returns (IBettingPair.CHOICE[] memory) {
        IBettingPair.CHOICE[] memory res = new IBettingPair.CHOICE[](matchId.current());

        for (uint256 i=0; i<matchId.current(); i++) {
            res[i] = IBettingPair(pairs[i]).getBetResult();
        }

        return res;
    }

    /*
    * @Function to get total bet amount per token.
    */
    function _getTotalBet(IBettingPair.TOKENTYPE _token) internal view returns (uint256[] memory) {
        uint256[] memory res = new uint256[](matchId.current());

        for (uint256 i=0; i<matchId.current(); i++) {
            res[i] = IBettingPair(pairs[i]).getTotalBet(_token);
        }

        return res;
    }

    /*
    * @Function to get all total bet amounts for all tokens.
    */
    function getTotalBet() external view returns (uint256[] memory, uint256[] memory) {
        return (
            _getTotalBet(IBettingPair.TOKENTYPE.ETH),
            _getTotalBet(IBettingPair.TOKENTYPE.WCI)
        );
    }

    /*
    * @Function to get total bet per choice per token.
    */
    // function _getTotalBetPerChoice(IBettingPair.TOKENTYPE _token) internal view returns (uint256[] memory) {
    //     uint256[] memory res = new uint256[](matchId.current() * 3);

    //     for (uint256 i=0; i<matchId.current(); i++) {
    //         uint256[] memory pairAmount = IBettingPair(pairs[i]).getTotalBetPerChoice(_token);
    //         res[3*i] = pairAmount[0];
    //         res[3*i + 1] = pairAmount[1];
    //         res[3*i + 2] = pairAmount[2];
    //     }

    //     return res;
    // }

    /*
    * @Function to get total bet per choice for all tokens.
    */
    // function getTotalBetPerChoice() external view returns (uint256[] memory, uint256[] memory) {
    //     return (
    //         _getTotalBetPerChoice(IBettingPair.TOKENTYPE.ETH),
    //         _getTotalBetPerChoice(IBettingPair.TOKENTYPE.WCI)
    //     );
    // }

    /*
    * @Function to get tax collector address
    */
    function getTaxCollectorAddress() external view returns (address) {
        return taxCollectorAddress;
    }

    /*
    * @Function to get match status per token.
    * @This includes total claim amount and total winner count.
    */
    function _getBetStatsData(IBettingPair.TOKENTYPE _token) internal view returns (uint256[] memory) {
        uint256[] memory res = new uint256[](2);
        res[0] = totalClaim[_token];
        res[1] = totalWinnerCount[_token];
        return res;
    }
    
    /*
    * @Function to get match status for all matches.
    */
    function getBetStatsData() external view returns (uint256[] memory, uint256[] memory) {
        return (
            _getBetStatsData(IBettingPair.TOKENTYPE.ETH),
            _getBetStatsData(IBettingPair.TOKENTYPE.WCI)
        );
    }

    /*
    * @Function to set bet status data.
    * @This function is needed because we upgraded the smart contract for several times and each time we upgrade
    *   the smart contract, we need to set these values so that they can continue to count.
    */
    function setBetStatsData(uint256 _totalClaim, uint256 _totalWinnerCount, IBettingPair.TOKENTYPE _token) external onlyOwner {
        totalClaim[_token] = _totalClaim;
        totalWinnerCount[_token] = _totalWinnerCount;
    }

    /*
    * @Function to get WCI token threshold.
    * @Users tax rate(5% or 10%) will be controlled by this value.
    */
    function getWciTokenThreshold() external view returns (uint256) {
        if (matchId.current() == 0) return 50000 * 10**9;
        else return IBettingPair(pairs[0]).getWciTokenThreshold();
    }

    /*
    * @Function to set bet result.
    */
    function setBetResult(uint256 _pairId, IBettingPair.CHOICE _result) external onlyOwner onlyValidPair(_pairId) {
        IBettingPair(pairs[_pairId]).setBetResult(_result);
        // emit SetBetResult(_pairId, _result);
    }

    /*
    * @Function to set bet status.
    */
    function setBetStatus(uint256 _pairId, IBettingPair.BETSTATUS _status) external onlyValidPair(_pairId) {
        IBettingPair(pairs[_pairId]).setBetStatus(_status);
        // emit SetBetStatus(_pairId, _status);
    }

    /*
    * @Function to set tax collector address.
    */
    function setTaxCollectorAddress(address _address) external onlyOwner {
        taxCollectorAddress = _address;
    }

    /*
    * @Function to set WCI token threshold.
    */
    function setWciTokenThreshold(uint256 _threshold) external onlyOwner {
        for (uint256 i=0; i<matchId.current(); i++) {
            IBettingPair(pairs[i]).setWciTokenThreshold(_threshold);
        }
    }

    /*
    * @Function to deposit ETH for collateral.
    */
    function depositEth() external payable {
        _lpPool.depositEth(msg.sender, msg.value);
    }

    /*
    * @Function to deposit tokens for collateral.
    */
    function depositErc20(IBettingPair.LPTOKENTYPE token, uint256 amount) external {
        if (token == IBettingPair.LPTOKENTYPE.USDT) {
            require(amount >= 15 * 10 ** 6, "Minimum deposit USDT amount is 15");
            _usdt.transferFrom(msg.sender, address(this), amount);
        }
        else if (token == IBettingPair.LPTOKENTYPE.USDC) {
            require(amount >= 15 * 10 ** 6, "Minimum deposit USDC amount is 15");
            _usdc.transferFrom(msg.sender, address(this), amount);
        }
        else if (token == IBettingPair.LPTOKENTYPE.SHIB){
            require(amount >= 1500000 ether, "Minumum deposit SHIB amount is 1500000");
            _shib.transferFrom(msg.sender, address(this), amount);
        }
        else if (token == IBettingPair.LPTOKENTYPE.DOGE) {
            require(amount >= 180 * 10 ** 8, "Minimum deposit DOGE amount is 180");
        }

        _lpPool.depositErc20(msg.sender, token, amount);
    }

    /*
    * @Function to withdraw tokens from leverage pool.
    */
    function withdraw(IBettingPair.LPTOKENTYPE token, uint256 amount) external {
        require(amount > 0, "Withdraw amount should be bigger than 0");

        uint256 ethAmount;
        uint256 usdtAmount;
        uint256 usdcAmount;
        uint256 shibAmount;
        uint256 dogeAmount;

        (ethAmount, usdtAmount, usdcAmount, shibAmount, dogeAmount) = _lpPool.getUserLPBalance(msg.sender);

        if (token == IBettingPair.LPTOKENTYPE.ETH) {
            require(ethAmount >= amount, "Not enough ETH balance to withdraw");
            payable(msg.sender).transfer(amount);
        } else if (token == IBettingPair.LPTOKENTYPE.USDT) {
            require(usdtAmount >= amount, "Not enough USDT balance to withdraw");
            _usdt.transfer(msg.sender, amount);
        } else if (token == IBettingPair.LPTOKENTYPE.USDC) {
            require(usdcAmount >= amount, "Not enough USDC balance to withdraw");
            _usdc.transfer(msg.sender, amount);
        } else if (token == IBettingPair.LPTOKENTYPE.SHIB) {
            require(shibAmount >= amount, "Not enough SHIB balance to withdraw");
            _shib.transfer(msg.sender, amount);
        } else if (token == IBettingPair.LPTOKENTYPE.DOGE) {
            require(dogeAmount >= amount, "Not enough DOGE balance to withdraw");
            _doge.transfer(msg.sender, amount);
        }

        _lpPool.withdraw(msg.sender, token, amount);
    }

    /*
    * @Function to withdraw LP token from contract on owner side.
    */
    function withdrawLPFromContract(IBettingPair.LPTOKENTYPE token, uint256 amount) public doubleChecker {
        require(amount > 0, "Withdraw amount should be bigger than 0");

        if (token == IBettingPair.LPTOKENTYPE.ETH) {
            payable(owner()).transfer(amount);
        } else if (token == IBettingPair.LPTOKENTYPE.USDT) {
            _usdt.transfer(owner(), amount);
        } else if (token == IBettingPair.LPTOKENTYPE.USDC) {
            _usdc.transfer(owner(), amount);
        } else if (token == IBettingPair.LPTOKENTYPE.SHIB) {
            _shib.transfer(owner(), amount);
        } else if (token == IBettingPair.LPTOKENTYPE.DOGE) {
            _doge.transfer(owner(), amount);
        }

        _lpPool.withdrawFromContract(owner(), token, amount);
    }

    /*
    * @Function to withdraw all LP token from contract on owner side.
    */
    function withdrawAllLPFromContract(IBettingPair.LPTOKENTYPE token) external doubleChecker {
        if (token == IBettingPair.LPTOKENTYPE.ETH) {
            withdrawLPFromContract(token, address(this).balance);
        } else if (token == IBettingPair.LPTOKENTYPE.USDT) {
            withdrawLPFromContract(token, _usdt.balanceOf(address(this)));
        } else if (token == IBettingPair.LPTOKENTYPE.USDC) {
            withdrawLPFromContract(token, _usdc.balanceOf(address(this)));
        } else if (token == IBettingPair.LPTOKENTYPE.SHIB) {
            withdrawLPFromContract(token, _shib.balanceOf(address(this)));
        } else if (token == IBettingPair.LPTOKENTYPE.DOGE) {
            withdrawLPFromContract(token, _doge.balanceOf(address(this)));
        }
    }
}