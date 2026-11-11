package com.acme.modres;

import com.google.gson.Gson;

import java.io.IOException;
import java.io.PrintWriter;
import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.Map;

import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

@WebServlet({ Constants.CALCULATE_PATH })
public class CalculatorServlet extends HttpServlet {
  private static final long serialVersionUID = 1L;

  private static final Gson GSON = new Gson();

  @Override
  protected void doGet(HttpServletRequest request, HttpServletResponse response)
      throws ServletException, IOException {

    String aParam = request.getParameter(Constants.PARAM_A);
    String bParam = request.getParameter(Constants.PARAM_B);
    String opParam = request.getParameter(Constants.PARAM_OP);

    if (isBlank(aParam) || isBlank(bParam) || isBlank(opParam)) {
      writeError(response, "Missing required parameter: a, b and op are required");
      return;
    }

    BigDecimal a;
    BigDecimal b;
    try {
      a = new BigDecimal(aParam.trim());
      b = new BigDecimal(bParam.trim());
    } catch (NumberFormatException e) {
      writeError(response, "Parameters a and b must be valid numbers");
      return;
    }

    ArithmeticCalculator.Operation op;
    try {
      op = ArithmeticCalculator.Operation.fromString(opParam);
    } catch (IllegalArgumentException e) {
      writeError(response, "Unknown operation: op must be one of add, subtract, multiply, divide, modulo");
      return;
    }

    BigDecimal result;
    try {
      result = ArithmeticCalculator.calculate(a, b, op);
    } catch (ArithmeticException e) {
      writeError(response, "Division or modulo by zero is not allowed");
      return;
    }

    Map<String, String> body = new LinkedHashMap<String, String>();
    body.put("a", a.toPlainString());
    body.put("b", b.toPlainString());
    body.put("op", op.name().toLowerCase());
    body.put("result", result.toPlainString());
    write(response, HttpServletResponse.SC_OK, body);
  }

  private static boolean isBlank(String s) {
    return s == null || s.trim().isEmpty();
  }

  private static void writeError(HttpServletResponse response, String message) throws IOException {
    Map<String, String> body = new LinkedHashMap<String, String>();
    body.put("error", message);
    write(response, HttpServletResponse.SC_BAD_REQUEST, body);
  }

  private static void write(HttpServletResponse response, int status, Map<String, String> body)
      throws IOException {
    response.setStatus(status);
    response.setContentType("application/json");
    response.setCharacterEncoding("UTF-8");
    PrintWriter out = response.getWriter();
    out.print(GSON.toJson(body));
    out.flush();
  }
}
