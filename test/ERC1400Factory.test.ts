import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ERC1400, ERC1400Whitelist, ERC1400Factory } from "../typechain-types";

describe("ERC1400Factory", function () {
  const TOKEN_NAME = "Security Token";
  const TOKEN_SYMBOL = "SEC";
  const GRANULARITY = 1n;
  const DEFAULT_PARTITION = ethers.zeroPadValue("0x00", 32);

  async function deployFactoryFixture() {
    const [owner, deployer1, deployer2, alice, bob] = await ethers.getSigners();

    // Deploy implementations
    const ERC1400 = await ethers.getContractFactory("ERC1400");
    const erc1400Implementation = await ERC1400.deploy();
    await erc1400Implementation.waitForDeployment();

    const ERC1400Whitelist = await ethers.getContractFactory("ERC1400Whitelist");
    const whitelistImplementation = await ERC1400Whitelist.deploy();
    await whitelistImplementation.waitForDeployment();

    // Deploy factory
    const ERC1400Factory = await ethers.getContractFactory("ERC1400Factory");
    const factory = await ERC1400Factory.deploy(
      await erc1400Implementation.getAddress(),
      await whitelistImplementation.getAddress()
    );
    await factory.waitForDeployment();

    return {
      factory,
      erc1400Implementation,
      whitelistImplementation,
      owner,
      deployer1,
      deployer2,
      alice,
      bob,
    };
  }

  describe("Deployment", function () {
    it("Should set implementations correctly", async function () {
      const { factory, erc1400Implementation, whitelistImplementation } =
        await loadFixture(deployFactoryFixture);

      expect(await factory.erc1400Implementation()).to.equal(
        await erc1400Implementation.getAddress()
      );
      expect(await factory.whitelistImplementation()).to.equal(
        await whitelistImplementation.getAddress()
      );
    });

    it("Should set owner correctly", async function () {
      const { factory, owner } = await loadFixture(deployFactoryFixture);
      expect(await factory.owner()).to.equal(owner.address);
    });

    it("Should revert with zero implementation address", async function () {
      const { whitelistImplementation } = await loadFixture(deployFactoryFixture);

      const ERC1400Factory = await ethers.getContractFactory("ERC1400Factory");
      await expect(
        ERC1400Factory.deploy(
          ethers.ZeroAddress,
          await whitelistImplementation.getAddress()
        )
      ).to.be.revertedWithCustomError(ERC1400Factory, "InvalidImplementation");
    });
  });

  describe("Token Deployment", function () {
    it("Should deploy a new token", async function () {
      const { factory, deployer1 } = await loadFixture(deployFactoryFixture);

      const tx = await factory
        .connect(deployer1)
        .deployToken(TOKEN_NAME, TOKEN_SYMBOL, GRANULARITY, [], [DEFAULT_PARTITION]);

      const receipt = await tx.wait();
      const event = receipt?.logs.find((log) => {
        try {
          const parsed = factory.interface.parseLog({
            topics: log.topics as string[],
            data: log.data,
          });
          return parsed?.name === "TokenDeployed";
        } catch {
          return false;
        }
      });

      expect(event).to.not.be.undefined;
    });

    it("Should register token in factory", async function () {
      const { factory, deployer1 } = await loadFixture(deployFactoryFixture);

      await factory
        .connect(deployer1)
        .deployToken(TOKEN_NAME, TOKEN_SYMBOL, GRANULARITY, [], [DEFAULT_PARTITION]);

      const tokens = await factory.getAllTokens();
      expect(tokens).to.have.lengthOf(1);
    });

    it("Should track deployer correctly", async function () {
      const { factory, deployer1 } = await loadFixture(deployFactoryFixture);

      await factory
        .connect(deployer1)
        .deployToken(TOKEN_NAME, TOKEN_SYMBOL, GRANULARITY, [], [DEFAULT_PARTITION]);

      const tokens = await factory.getTokensByDeployer(deployer1.address);
      expect(tokens).to.have.lengthOf(1);
    });

    it("Should deploy multiple tokens", async function () {
      const { factory, deployer1, deployer2 } = await loadFixture(
        deployFactoryFixture
      );

      await factory
        .connect(deployer1)
        .deployToken("Token A", "TKA", GRANULARITY, [], [DEFAULT_PARTITION]);

      await factory
        .connect(deployer2)
        .deployToken("Token B", "TKB", GRANULARITY, [], [DEFAULT_PARTITION]);

      await factory
        .connect(deployer1)
        .deployToken("Token C", "TKC", GRANULARITY, [], [DEFAULT_PARTITION]);

      expect(await factory.getTokenCount()).to.equal(3n);
      expect(await factory.getTokensByDeployer(deployer1.address)).to.have.lengthOf(2);
      expect(await factory.getTokensByDeployer(deployer2.address)).to.have.lengthOf(1);
    });

    it("Should emit TokenDeployed event", async function () {
      const { factory, deployer1 } = await loadFixture(deployFactoryFixture);

      await expect(
        factory
          .connect(deployer1)
          .deployToken(TOKEN_NAME, TOKEN_SYMBOL, GRANULARITY, [], [DEFAULT_PARTITION])
      )
        .to.emit(factory, "TokenDeployed")
        .withArgs(
          (token: string) => ethers.isAddress(token),
          deployer1.address,
          TOKEN_NAME,
          TOKEN_SYMBOL,
          false
        );
    });
  });

  describe("Deterministic Deployment", function () {
    it("Should deploy token at predicted address", async function () {
      const { factory, deployer1 } = await loadFixture(deployFactoryFixture);
      const salt = ethers.encodeBytes32String("SALT_1");

      const predictedAddress = await factory.computeTokenAddress(
        TOKEN_NAME,
        TOKEN_SYMBOL,
        GRANULARITY,
        [],
        [DEFAULT_PARTITION],
        salt
      );

      await factory
        .connect(deployer1)
        .deployTokenDeterministic(
          TOKEN_NAME,
          TOKEN_SYMBOL,
          GRANULARITY,
          [],
          [DEFAULT_PARTITION],
          salt
        );

      const tokens = await factory.getAllTokens();
      expect(tokens[0]).to.equal(predictedAddress);
    });

    it("Should emit TokenDeployed with deterministic flag", async function () {
      const { factory, deployer1 } = await loadFixture(deployFactoryFixture);
      const salt = ethers.encodeBytes32String("SALT_2");

      await expect(
        factory
          .connect(deployer1)
          .deployTokenDeterministic(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            GRANULARITY,
            [],
            [DEFAULT_PARTITION],
            salt
          )
      )
        .to.emit(factory, "TokenDeployed")
        .withArgs(
          (token: string) => ethers.isAddress(token),
          deployer1.address,
          TOKEN_NAME,
          TOKEN_SYMBOL,
          true
        );
    });

    it("Should produce same address with same parameters", async function () {
      const { factory } = await loadFixture(deployFactoryFixture);
      const salt = ethers.encodeBytes32String("SALT_3");

      const address1 = await factory.computeTokenAddress(
        TOKEN_NAME,
        TOKEN_SYMBOL,
        GRANULARITY,
        [],
        [DEFAULT_PARTITION],
        salt
      );

      const address2 = await factory.computeTokenAddress(
        TOKEN_NAME,
        TOKEN_SYMBOL,
        GRANULARITY,
        [],
        [DEFAULT_PARTITION],
        salt
      );

      expect(address1).to.equal(address2);
    });

    it("Should produce different addresses with different salts", async function () {
      const { factory } = await loadFixture(deployFactoryFixture);
      const salt1 = ethers.encodeBytes32String("SALT_A");
      const salt2 = ethers.encodeBytes32String("SALT_B");

      const address1 = await factory.computeTokenAddress(
        TOKEN_NAME,
        TOKEN_SYMBOL,
        GRANULARITY,
        [],
        [DEFAULT_PARTITION],
        salt1
      );

      const address2 = await factory.computeTokenAddress(
        TOKEN_NAME,
        TOKEN_SYMBOL,
        GRANULARITY,
        [],
        [DEFAULT_PARTITION],
        salt2
      );

      expect(address1).to.not.equal(address2);
    });
  });

  describe("Whitelist Validator Deployment", function () {
    it("Should deploy whitelist validator", async function () {
      const { factory, deployer1 } = await loadFixture(deployFactoryFixture);

      const tx = await factory.connect(deployer1).deployWhitelistValidator(true);
      const receipt = await tx.wait();

      const event = receipt?.logs.find((log) => {
        try {
          const parsed = factory.interface.parseLog({
            topics: log.topics as string[],
            data: log.data,
          });
          return parsed?.name === "ValidatorDeployed";
        } catch {
          return false;
        }
      });

      expect(event).to.not.be.undefined;
    });

    it("Should deploy validator with correct active status", async function () {
      const { factory, deployer1 } = await loadFixture(deployFactoryFixture);

      const tx = await factory.connect(deployer1).deployWhitelistValidator(false);
      const receipt = await tx.wait();

      // Get validator address from event
      const event = receipt?.logs.find((log) => {
        try {
          const parsed = factory.interface.parseLog({
            topics: log.topics as string[],
            data: log.data,
          });
          return parsed?.name === "ValidatorDeployed";
        } catch {
          return false;
        }
      });

      if (event) {
        const parsed = factory.interface.parseLog({
          topics: event.topics as string[],
          data: event.data,
        });
        const validatorAddress = parsed?.args[0];

        const ERC1400Whitelist = await ethers.getContractFactory("ERC1400Whitelist");
        const validator = ERC1400Whitelist.attach(validatorAddress) as ERC1400Whitelist;

        expect(await validator.isWhitelistActive()).to.be.false;
      }
    });
  });

  describe("Token Functionality", function () {
    it("Deployed token should be functional", async function () {
      const { factory, deployer1, alice, bob } = await loadFixture(
        deployFactoryFixture
      );

      const tx = await factory
        .connect(deployer1)
        .deployToken(TOKEN_NAME, TOKEN_SYMBOL, GRANULARITY, [], [DEFAULT_PARTITION]);

      const receipt = await tx.wait();
      const event = receipt?.logs.find((log) => {
        try {
          const parsed = factory.interface.parseLog({
            topics: log.topics as string[],
            data: log.data,
          });
          return parsed?.name === "TokenDeployed";
        } catch {
          return false;
        }
      });

      const parsed = factory.interface.parseLog({
        topics: event?.topics as string[],
        data: event?.data || "",
      });
      const tokenAddress = parsed?.args[0];

      const ERC1400 = await ethers.getContractFactory("ERC1400");
      const token = ERC1400.attach(tokenAddress) as ERC1400;

      // Verify token is owned by deployer
      expect(await token.owner()).to.equal(deployer1.address);

      // Issue and transfer tokens
      const amount = ethers.parseEther("1000");
      await token.connect(deployer1).issue(alice.address, amount, "0x");
      expect(await token.balanceOf(alice.address)).to.equal(amount);

      await token.connect(alice).transfer(bob.address, ethers.parseEther("100"));
      expect(await token.balanceOf(bob.address)).to.equal(ethers.parseEther("100"));
    });
  });

  describe("Admin Functions", function () {
    it("Should update ERC1400 implementation", async function () {
      const { factory, owner } = await loadFixture(deployFactoryFixture);

      const ERC1400 = await ethers.getContractFactory("ERC1400");
      const newImplementation = await ERC1400.deploy();
      await newImplementation.waitForDeployment();

      await factory
        .connect(owner)
        .setERC1400Implementation(await newImplementation.getAddress());

      expect(await factory.erc1400Implementation()).to.equal(
        await newImplementation.getAddress()
      );
    });

    it("Should emit ImplementationUpdated event", async function () {
      const { factory, owner, erc1400Implementation } = await loadFixture(
        deployFactoryFixture
      );

      const ERC1400 = await ethers.getContractFactory("ERC1400");
      const newImplementation = await ERC1400.deploy();
      await newImplementation.waitForDeployment();

      await expect(
        factory
          .connect(owner)
          .setERC1400Implementation(await newImplementation.getAddress())
      )
        .to.emit(factory, "ImplementationUpdated")
        .withArgs(
          await erc1400Implementation.getAddress(),
          await newImplementation.getAddress(),
          "ERC1400"
        );
    });

    it("Should revert non-owner updating implementation", async function () {
      const { factory, deployer1 } = await loadFixture(deployFactoryFixture);

      const ERC1400 = await ethers.getContractFactory("ERC1400");
      const newImplementation = await ERC1400.deploy();
      await newImplementation.waitForDeployment();

      await expect(
        factory
          .connect(deployer1)
          .setERC1400Implementation(await newImplementation.getAddress())
      ).to.be.revertedWithCustomError(factory, "OwnableUnauthorizedAccount");
    });

    it("Should revert setting zero address implementation", async function () {
      const { factory, owner } = await loadFixture(deployFactoryFixture);

      await expect(
        factory.connect(owner).setERC1400Implementation(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(factory, "InvalidImplementation");
    });
  });
});
