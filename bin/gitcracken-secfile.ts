import chalk from "chalk";
import { program } from "commander";

import {AppId, Logo, SecFile} from "../";

program
  .name("gitcracken-secfile")
  .description("read GitKraken secFile")
  .option("-i, --appid <id>", "AppId for secFile decrypt", AppId.read())
  .arguments("[files...]")
  .action((files?: string[]) => {
    Logo.print();
    const opts = program.opts();
    for (const file of files || []) {
      console.log(`${chalk.green("==>")} ${chalk.bold(file)}`);
      const secFile = new SecFile(file, opts.appid);
      secFile.read();
      console.log(JSON.stringify(secFile.data, null, 2));
    }
  })
  .parse(process.argv);
