package com.acme.modres;

import java.math.BigDecimal;
import java.math.MathContext;

/**
 * Stateless BigDecimal arithmetic, independent of any servlet container.
 */
public final class ArithmeticCalculator {

  public enum Operation {
    ADD, SUBTRACT, MULTIPLY, DIVIDE, MODULO;

    /**
     * Case-insensitive lookup.
     *
     * @throws IllegalArgumentException if the name is null or unknown
     */
    public static Operation fromString(String name) {
      if (name != null) {
        for (Operation o : values()) {
          if (o.name().equalsIgnoreCase(name.trim())) {
            return o;
          }
        }
      }
      throw new IllegalArgumentException("Unknown operation");
    }
  }

  private ArithmeticCalculator() {
  }

  /**
   * @throws ArithmeticException on division or modulo by zero
   */
  public static BigDecimal calculate(BigDecimal a, BigDecimal b, Operation op) {
    switch (op) {
      case ADD:
        return a.add(b);
      case SUBTRACT:
        return a.subtract(b);
      case MULTIPLY:
        return a.multiply(b);
      case DIVIDE:
        if (b.signum() == 0) {
          throw new ArithmeticException("Division by zero");
        }
        return a.divide(b, MathContext.DECIMAL64);
      case MODULO:
        if (b.signum() == 0) {
          throw new ArithmeticException("Modulo by zero");
        }
        return a.remainder(b);
      default:
        throw new IllegalArgumentException("Unknown operation");
    }
  }
}
