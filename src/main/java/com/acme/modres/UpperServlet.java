package com.acme.modres;

import java.io.IOException;
import java.io.PrintWriter;

import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

@WebServlet("/resorts/upper")
public class UpperServlet extends HttpServlet {

  private static final long serialVersionUID = 1L;

  @Override
  protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
    response.setContentType("text/html");

    String originalStr = request.getParameter("input");
    if (originalStr == null) {
      originalStr = "";
    }

    String newStr = originalStr.toUpperCase();
    newStr = encodeDataString(newStr);

    PrintWriter out = response.getWriter();
    out.print("<br/><b>upper case input " + newStr + "</b>");
  }

  /**
   * Standard HTML encoding (replaces WebSphere ResponseUtils.encodeDataString).
   */
  private static String encodeDataString(String input) {
    StringBuilder sb = new StringBuilder(input.length());
    for (char c : input.toCharArray()) {
      switch (c) {
        case '<': sb.append("&lt;"); break;
        case '>': sb.append("&gt;"); break;
        case '&': sb.append("&amp;"); break;
        case '"': sb.append("&quot;"); break;
        case '\'': sb.append("&#39;"); break;
        default: sb.append(c);
      }
    }
    return sb.toString();
  }
}
