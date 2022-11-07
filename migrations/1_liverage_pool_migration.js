const LeveragePool = artifacts.require("LeveragePool");

module.exports = function(deployer) {
  deployer.deploy(LeveragePool);
};