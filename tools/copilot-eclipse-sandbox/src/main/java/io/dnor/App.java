package io.dnor;

import java.util.logging.Logger;

public class App {

  private static final Logger LOGGER = Logger.getLogger(App.class.getName());
  private static final String VERSION = "1.0.0";

  public static void main(String[] args) {
    if (args.length == 0) {
      System.out.println("copilot-eclipse-sandbox v" + VERSION + " — up");
      return;
    }

    int rc = run(args);
    if (rc != 0) {
      System.exit(rc);
    }
  }

  public static int run(String[] args) {
    if (args.length == 0) {
      return 0;
    }
    String cmd = args[0];
    switch (cmd) {
      case "-h":
      case "--help":
        printUsage();
        return 0;
      case "--version":
      case "-v":
        System.out.println(VERSION);
        return 0;
      case "greet":
        String name = (args.length > 1) ? args[1] : "World";
        LOGGER.info("Executando greet para: " + name);
        System.out.println("Hello, " + name + "!");
        return 0;
      default:
        System.err.println("Comando desconhecido: " + cmd);
        printUsage();
        return 1;
    }
  }

  private static void printUsage() {
    System.out.println("Uso: java -cp target/classes io.dnor.App [comando]");
    System.out.println("Comandos:");
    System.out.println("  greet [nome]  — imprime uma saudacao (default: World)");
    System.out.println("  -h, --help    — mostra esta ajuda");
    System.out.println("  -v, --version — mostra a versao");
  }
}
