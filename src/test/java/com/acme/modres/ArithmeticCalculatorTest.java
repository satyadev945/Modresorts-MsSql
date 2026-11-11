package com.acme.modres;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import com.acme.modres.ArithmeticCalculator.Operation;

import java.math.BigDecimal;

import org.junit.jupiter.api.Test;

class ArithmeticCalculatorTest {

  private static String calc(String a, String b, Operation op) {
    return ArithmeticCalculator.calculate(new BigDecimal(a), new BigDecimal(b), op).toPlainString();
  }

  @Test
  void add() {
    assertEquals("5", calc("2", "3", Operation.ADD));
  }

  @Test
  void subtract() {
    assertEquals("-1", calc("2", "3", Operation.SUBTRACT));
  }

  @Test
  void multiply() {
    assertEquals("6", calc("2", "3", Operation.MULTIPLY));
  }

  @Test
  void divide() {
    assertEquals("2", calc("6", "3", Operation.DIVIDE));
  }

  @Test
  void modulo() {
    assertEquals("1", calc("7", "3", Operation.MODULO));
  }

  @Test
  void decimalsAvoidFloatingPointError() {
    assertEquals("0.3", calc("0.1", "0.2", Operation.ADD));
  }

  @Test
  void negatives() {
    assertEquals("-6", calc("-2", "3", Operation.MULTIPLY));
    assertEquals("-1", calc("-7", "3", Operation.MODULO));
  }

  @Test
  void largeValues() {
    assertEquals("100000000000000000000000000000000000000000000000000",
        calc("99999999999999999999999999999999999999999999999999", "1", Operation.ADD));
  }

  @Test
  void nonTerminatingDivideDoesNotThrow() {
    assertEquals("0.3333333333333333", calc("1", "3", Operation.DIVIDE));
  }

  @Test
  void divideByZeroThrows() {
    assertThrows(ArithmeticException.class, () -> calc("1", "0", Operation.DIVIDE));
  }

  @Test
  void moduloByZeroThrows() {
    assertThrows(ArithmeticException.class, () -> calc("1", "0", Operation.MODULO));
  }

  @Test
  void operationLookupIsCaseInsensitive() {
    assertEquals(Operation.DIVIDE, Operation.fromString("DiVide"));
  }

  @Test
  void unknownOperationThrows() {
    assertThrows(IllegalArgumentException.class, () -> Operation.fromString("power"));
  }
}
