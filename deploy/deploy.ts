// deploy/deploy.ts — простой деплой только CipherGuess
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network, ethers } = hre;
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  // N берём из ENV или 100 по умолчанию
  const maxStr = process.env.GUESS_MAX_VALUE ?? "100";
  const N = Number(maxStr);
  if (!Number.isInteger(N) || N < 0 || N > 65535) {
    throw new Error(`Invalid GUESS_MAX_VALUE="${maxStr}". Must be integer in [0..65535].`);
  }

  const wait = Number(process.env.WAIT_CONFIRMS ?? "1");

  log(`Deployer=${deployer} | Network=${network.name} | N=${N}`);

  // деплой контракта
  const res = await deploy("CipherGuess", {
    from: deployer,
    args: [N], // constructor(uint16 _N)
    log: true,
    waitConfirmations: wait,
    skipIfAlreadyDeployed: false,
  });

  log(`CipherGuess deployed at ${res.address} (N=${N}) on ${network.name}`);

  // опционально: вывести версию, если функция есть
  try {
    const ctr = await ethers.getContractAt("CipherGuess", res.address);
    const ver = await ctr.version();
    log(`CipherGuess version: ${ver}`);
  } catch {
    // если в контракте нет version() — просто молчим
  }

  log(`ℹ️ После деплоя установи секрет через UI (Owner tools → Reseed).`);
};

export default func;
func.tags = ["CipherGuess"];
