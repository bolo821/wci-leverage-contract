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
    // Counters.Counter matchId;           // variable for managing match id
    uint256 matchId;
    address taxCollectorAddress = 0x41076e8DEbC1C51E0225CF73Cc23Ebd9D20424CE;        // Tax collector address
    uint256 totalClaimEth;
    uint256 totalClaimWci;
    uint256 totalWinnerCountEth;
    uint256 totalWinnerCountWci;

    IERC20 wciToken = IERC20(0xC5a9BC46A7dbe1c6dE493E84A18f02E70E2c5A32);
    IERC20USDT _usdt = IERC20USDT(0xdAC17F958D2ee523a2206206994597C13D831ec7);  // USDT token
    IERC20 _usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);          // USDC token
    IERC20 _shib = IERC20(0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE);          // SHIB token
    IERC20 _doge = IERC20(0x4206931337dc273a630d328dA6441786BfaD668f);          // DOGE token

    LeveragePool _lpPool;

    constructor() {
        _lpPool = new LeveragePool();
    }

    /*
    * @Check if the input pair id is valid
    */
    modifier onlyValidPair(uint256 _id) {
        require(_id >= 0 && _id < matchId, "Invalid pair id.");
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
        pairs[matchId] = address(_pair);
        matchId ++;
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
        require(ethInLPPool >= (msg.value).mul(_multiplier.sub(1)), "You don't have enough collaterals for that multiplier.");

        uint256 ethCol;     // ETH collateral amount
        uint256 usdtCol;    // USDT collateral amount
        uint256 usdcCol;    // USDC collateral amount
        uint256 shibCol;    // SHIB collateral amount
        uint256 dogeCol;    // DOGE collateral amount

        (ethCol, usdtCol, usdcCol, shibCol, dogeCol) = _lpPool.calcLockTokenAmountsAsCollateral(msg.sender, (msg.value).mul(_multiplier.sub(1)));
        _lpPool.lock(msg.sender, ethCol, usdtCol, usdcCol, shibCol, dogeCol);
        _lpPool.unlock(owner(), ethCol, usdtCol, usdcCol, shibCol, dogeCol);

        IBettingPair(pairs[_pairId]).bet(msg.sender, msg.value, _multiplier, _choice, IBettingPair.TOKENTYPE.ETH,
            ethCol, usdtCol, usdcCol, shibCol, dogeCol);
    }

    /*
    * Function for betting with WCI.
    * This function should be separated from ETH and other tokens because this token's transferFrom function has default tax rate.
    */
    function betWCI(uint256 _pairId, uint256 _betAmount, IBettingPair.CHOICE _choice) external
        onlyValidPair(_pairId)
        betConditions(_betAmount, IBettingPair.TOKENTYPE.WCI)
    {
        wciToken.transferFrom(msg.sender, address(this), _betAmount);

        // Apply 5% tax to all bet amounts.
        IBettingPair(pairs[_pairId]).bet(msg.sender, _betAmount.mul(19).div(20), 1, _choice, IBettingPair.TOKENTYPE.WCI, 0, 0, 0, 0, 0);
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
            _lpPool.lock(owner(), claimInfo[2], claimInfo[3], claimInfo[4], claimInfo[5], claimInfo[6]);
        } else if (_token == IBettingPair.TOKENTYPE.WCI) {
            wciToken.transfer(msg.sender, _amountClaim);
        }
        
        if (_token == IBettingPair.TOKENTYPE.ETH) {
            totalClaimEth += _amountClaim;
            totalWinnerCountEth ++;
        } else {
            totalClaimWci += _amountClaim;
            totalWinnerCountWci ++;
        }
    }

    /*
    * @Function to withdraw tokens from router contract.
    */
    function withdrawPFromRouter(uint256 _amount, IBettingPair.TOKENTYPE _token) external doubleChecker {
        if (_token == IBettingPair.TOKENTYPE.ETH) {
            payable(owner()).transfer(_amount);
        } else if (_token == IBettingPair.TOKENTYPE.WCI) {
            wciToken.transfer(owner(), _amount);
        }
    }

    /*
    * @Function to get player bet information with triple data per match(per player choice).
    * @There are 3 types of information - first part(1/3 of total) is player bet amount information.
        Second part(1/3 of total) is multiplier information. Third part(1/3 of total) is player earning information.
    * @These information were separated before but merged to one function because of capacity of contract.
    */
    function getBetTripleInformation(address _player, IBettingPair.TOKENTYPE _token) external view returns (uint256[] memory) {
        uint256[] memory res = new uint256[](matchId * 9);

        for (uint256 i=0; i<matchId; i++) {
            uint256[] memory oneAmount = IBettingPair(pairs[i]).getPlayerBetAmount(_player, _token);
            res[i*3] = oneAmount[0];
            res[i*3 + 1] = oneAmount[1];
            res[i*3 + 2] = oneAmount[2];

            uint256[] memory oneMultiplier = IBettingPair(pairs[i]).calcMultiplier(_token);
            res[matchId*3 + i*3] = oneMultiplier[0];
            res[matchId*3 + i*3 + 1] = oneMultiplier[1];
            res[matchId*3 + i*3 + 2] = oneMultiplier[2];

            uint256[] memory oneClaim = IBettingPair(pairs[i]).calcEarning(_player, _token);
            res[matchId*6 + i*3] = oneClaim[0];
            res[matchId*6 + i*3 + 1] = oneClaim[1];
            res[matchId*6 + i*3 + 2] = oneClaim[2];
        }
        
        return res;
    }

    /*
    * @Function to get player bet information with single data per match.
    */
    function getBetSingleInformation(address _player, IBettingPair.TOKENTYPE _token) external view returns (uint256[] memory) {
        uint256[] memory res = new uint256[](matchId * 4);

        for (uint256 i=0; i<matchId; i++) {
            res[i] = IBettingPair(pairs[i]).getPlayerClaimHistory(_player, _token);
            res[matchId + i] = uint256(IBettingPair(pairs[i]).getBetStatus());
            res[matchId*2 + i] = uint256(IBettingPair(pairs[i]).getBetResult());
            res[matchId*3 + i] = IBettingPair(pairs[i]).getTotalBet(_token);
        }

        return res;
    }

    /*
    * @Function to get the newly creating match id.
    */
    function getMatchId() external view returns (uint256) {
        return matchId;
    }

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
    function getBetStatsData(IBettingPair.TOKENTYPE _token) external view returns (uint256, uint256) {
        if (_token == IBettingPair.TOKENTYPE.ETH) {
            return (totalClaimEth, totalWinnerCountEth);
        } else {
            return (totalClaimWci, totalWinnerCountWci);
        }
    }

    /*
    * @Function to set bet status data.
    * @This function is needed because we upgraded the smart contract for several times and each time we upgrade
    *   the smart contract, we need to set these values so that they can continue to count.
    */
    function setBetStatsData(uint256 _totalClaim, uint256 _totalWinnerCount, IBettingPair.TOKENTYPE _token) external onlyOwner {
        if (_token == IBettingPair.TOKENTYPE.ETH) {
            totalClaimEth = _totalClaim;
            totalWinnerCountEth = _totalWinnerCount;
        } else {
            totalClaimWci = _totalClaim;
            totalWinnerCountWci = _totalWinnerCount;
        }
    }

    /*
    * @Function to get WCI token threshold.
    * @Users tax rate(5% or 10%) will be controlled by this value.
    */
    function getWciTokenThreshold() external view returns (uint256) {
        if (matchId == 0) return 50000 * 10**9;
        else return IBettingPair(pairs[0]).getWciTokenThreshold();
    }

    /*
    * @Function to set bet result.
    */
    function setBetResult(uint256 _pairId, IBettingPair.CHOICE _result) external onlyOwner onlyValidPair(_pairId) {
        IBettingPair(pairs[_pairId]).setBetResult(_result);
    }

    /*
    * @Function to set bet status.
    */
    function setBetStatus(uint256 _pairId, IBettingPair.BETSTATUS _status) external onlyValidPair(_pairId) {
        IBettingPair(pairs[_pairId]).setBetStatus(_status);
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
        for (uint256 i=0; i<matchId; i++) {
            IBettingPair(pairs[i]).setWciTokenThreshold(_threshold);
        }
    }

    /*
    * @Function to deposit ETH for collateral.
    */
    function depositEth() external payable {
        require(msg.value >= 0.01 ether, "Minimum deposit amount is 0.01");

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
            _doge.transferFrom(msg.sender, address(this), amount);
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
    * @Function to get player's LP token balance.
    */
    function getUserLPBalance(address player) external view returns (uint256, uint256, uint256, uint256, uint256) {
        return _lpPool.getUserLPBalance(player);
    }

    /*
    * @Function to withdraw LP token from contract on owner side.
    */
    function withdrawLPFromContract(IBettingPair.LPTOKENTYPE token, uint256 amount) public doubleChecker {
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
}