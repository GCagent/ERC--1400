import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ethers } from "ethers";

/**
 * ERC1400 Direct Deployment Module
 *
 * This module directly deploys an ERC1400 token with a UUPS proxy,
 * bypassing the factory for simpler deployments.
 */
const ERC1400DirectModule = buildModule("ERC1400DirectModule", (m) => {
  // ============ Parameters ============

  const tokenName = m.getParameter("tokenName", "Security Token");
  const tokenSymbol = m.getParameter("tokenSymbol", "SEC");
  const granularity = m.getParameter("granularity", 1n);
  const whitelistActive = m.getParameter("whitelistActive", true);

  // Default partition (bytes32(0))
  const defaultPartition = ethers.zeroPadValue("0x00", 32);

  // ============ Deploy Implementation ============

  const erc1400Implementation = m.contract("ERC1400", [], {
    id: "ERC1400Implementation",
  });

  // ============ Deploy Proxy ============

  // Encode initialization data
  const initData = m.encodeFunctionCall(erc1400Implementation, "initialize", [
    tokenName,
    tokenSymbol,
    granularity,
    [], // Empty controllers array - owner will be added automatically
    [defaultPartition], // Default partitions
  ]);

  // Deploy ERC1967Proxy pointing to implementation
  const proxy = m.contract(
    "ERC1967Proxy",
    [erc1400Implementation, initData],
    {
      id: "ERC1400Proxy",
      after: [erc1400Implementation],
    }
  );

  // ============ Deploy Whitelist Validator (Optional) ============

  const whitelistImplementation = m.contract("ERC1400Whitelist", [], {
    id: "ERC1400WhitelistImplementation",
  });

  const whitelistInitData = m.encodeFunctionCall(
    whitelistImplementation,
    "initialize",
    [whitelistActive]
  );

  const whitelistProxy = m.contract(
    "ERC1967Proxy",
    [whitelistImplementation, whitelistInitData],
    {
      id: "ERC1400WhitelistProxy",
      after: [whitelistImplementation],
    }
  );

  return {
    erc1400Implementation,
    proxy,
    whitelistImplementation,
    whitelistProxy,
  };
});

export default ERC1400DirectModule;
