import chalk from "chalk";
import { program } from "commander";

import {AppId, Logo} from "../";

program
  .name("gitcracken-appid-generate")
  .description("generate GitKraken AppId")
  .option("-m, --mac <value>", "use specific mac address (or any other string)")
  .action(async () => {
    Logo.print();
    const opts = program.opts();
    console.log(
      `${chalk.green("==>")} Generated AppId ${chalk.green(
        opts.mac ? AppId.generate(opts.mac) : await AppId.generateAsync(),
      )}`,
    );
  })
  .parse(process.argv);
