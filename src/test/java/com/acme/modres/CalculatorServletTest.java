package com.acme.modres;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.io.PrintWriter;
import java.io.StringWriter;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.junit.jupiter.api.Test;

class CalculatorServletTest {

  private final CalculatorServlet servlet = new CalculatorServlet();

  private String call(String a, String b, String op, int expectedStatus) throws Exception {
    HttpServletRequest request = mock(HttpServletRequest.class);
    HttpServletResponse response = mock(HttpServletResponse.class);
    when(request.getParameter("a")).thenReturn(a);
    when(request.getParameter("b")).thenReturn(b);
    when(request.getParameter("op")).thenReturn(op);
    StringWriter sw = new StringWriter();
    when(response.getWriter()).thenReturn(new PrintWriter(sw));

    servlet.doGet(request, response);

    verify(response).setStatus(expectedStatus);
    verify(response).setContentType("application/json");
    verify(response).setCharacterEncoding("UTF-8");
    return sw.toString();
  }

  @Test
  void successReturnsResult() throws Exception {
    assertEquals("{\"a\":\"6\",\"b\":\"3\",\"op\":\"divide\",\"result\":\"2\"}",
        call("6", "3", "divide", 200));
  }

  @Test
  void opIsCaseInsensitive() throws Exception {
    assertEquals("{\"a\":\"1\",\"b\":\"2\",\"op\":\"add\",\"result\":\"3\"}",
        call("1", "2", "ADD", 200));
  }

  @Test
  void missingParameterReturns400() throws Exception {
    String body = call(null, "3", "add", 400);
    assertEquals(true, body.startsWith("{\"error\":"));
  }

  @Test
  void nonNumericReturns400() throws Exception {
    String body = call("abc", "3", "add", 400);
    assertEquals(true, body.startsWith("{\"error\":"));
  }

  @Test
  void unknownOpReturns400() throws Exception {
    String body = call("1", "2", "power", 400);
    assertEquals(true, body.startsWith("{\"error\":"));
  }

  @Test
  void divisionByZeroReturns400() throws Exception {
    String body = call("1", "0", "divide", 400);
    assertEquals(true, body.startsWith("{\"error\":"));
  }

  @Test
  void moduloByZeroReturns400() throws Exception {
    String body = call("1", "0", "modulo", 400);
    assertEquals(true, body.startsWith("{\"error\":"));
  }
}
