const TetherToken = artifacts.require("TetherToken");

module.exports = function(deployer) {
  deployer.deploy(TetherToken, 1000000, "Tether USD", "USDT", 6);
};