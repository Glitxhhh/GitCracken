import chalk from "chalk";
import { program } from "commander";

import {AppId, Logo} from "../src";

program
  .name("gitcracken-appid-read")
  .description("read GitKraken AppId from config")
  .option("-c, --config <file>", "path to config")
  .action(() => {
    Logo.print();
    const opts = program.opts();
    console.log(
      `${chalk.green("==>")} Current AppId ${chalk.green(
        AppId.read(opts.config) || "null",
      )}`,
    );
  })
  .parse(process.argv);
