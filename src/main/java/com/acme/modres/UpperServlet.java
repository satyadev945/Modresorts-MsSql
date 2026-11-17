package com.acme.modres;

import java.io.IOException;
import java.io.PrintWriter;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

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
    newStr = escapeHtml(newStr);

    PrintWriter out = response.getWriter();
    out.print("<br/><b>upper case input " + newStr + "</b>");
  }

  private static String escapeHtml(String s) {
    StringBuilder sb = new StringBuilder(s.length());
    for (char c : s.toCharArray()) {
      switch (c) {
        case '<' -> sb.append("&lt;");
        case '>' -> sb.append("&gt;");
        case '&' -> sb.append("&amp;");
        case '"' -> sb.append("&quot;");
        case '\'' -> sb.append("&#39;");
        default -> sb.append(c);
      }
    }
    return sb.toString();
  }
}
