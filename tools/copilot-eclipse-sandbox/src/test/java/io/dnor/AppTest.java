package io.dnor;

import static org.junit.jupiter.api.Assertions.assertEquals;
import org.junit.jupiter.api.Test;

class AppTest {

  @Test
  void run_noArgs_returnsZero() {
    int rc = App.run(new String[] {});
    assertEquals(0, rc);
  }

  @Test
  void run_greet_returnsZero() {
    int rc = App.run(new String[] { "greet", "Alice" });
    assertEquals(0, rc);
  }

  @Test
  void run_unknownCommand_returnsOne() {
    int rc = App.run(new String[] { "xpto" });
    assertEquals(1, rc);
  }

  @Test
  void run_version_returnsZero() {
    int rc = App.run(new String[] { "--version" });
    assertEquals(0, rc);
  }
}
