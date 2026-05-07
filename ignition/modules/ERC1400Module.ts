import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * ERC1400 Deployment Module
 *
 * This module deploys:
 * 1. ERC1400 Implementation (logic contract)
 * 2. ERC1400Whitelist Implementation (validator logic)
 * 3. ERC1400Factory (for deploying token instances)
 *
 * The factory can then be used to deploy individual token proxies.
 */
const ERC1400Module = buildModule("ERC1400Module", (m) => {
  // ============ Parameters ============

  // Token parameters (for direct deployment)
  const tokenName = m.getParameter("tokenName", "Security Token");
  const tokenSymbol = m.getParameter("tokenSymbol", "SEC");
  const granularity = m.getParameter("granularity", 1n);
  const deployDirect = m.getParameter("deployDirect", false);

  // ============ Deploy Implementations ============

  // Deploy ERC1400 implementation contract
  const erc1400Implementation = m.contract("ERC1400", [], {
    id: "ERC1400Implementation",
  });

  // Deploy ERC1400Whitelist implementation contract
  const whitelistImplementation = m.contract("ERC1400Whitelist", [], {
    id: "ERC1400WhitelistImplementation",
  });

  // ============ Deploy Factory ============

  // Deploy factory with implementations
  const factory = m.contract(
    "ERC1400Factory",
    [erc1400Implementation, whitelistImplementation],
    {
      id: "ERC1400Factory",
      after: [erc1400Implementation, whitelistImplementation],
    }
  );

  return {
    erc1400Implementation,
    whitelistImplementation,
    factory,
  };
});

export default ERC1400Module;
