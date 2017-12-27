var RangedIDRegistrar = artifacts.require("./RangedIDRegistrar.sol");
var PublicResolver = artifacts.require("./PublicResolver.sol"); // artifacts(npm)
var contract_json;
var addr;

module.exports = function(deployer) {
    deployer.deploy(RangedIDRegistrar);
    deployer.deploy(PublicResolver);
};
