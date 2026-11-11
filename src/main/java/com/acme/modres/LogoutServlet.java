package com.acme.modres;

import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpSession;

import java.io.IOException;

@WebServlet({ "/logout" })
public class LogoutServlet extends HttpServlet {
  private static final long serialVersionUID = 1L;

  @Override
  protected void doGet(HttpServletRequest request,
      HttpServletResponse response) throws IOException {

    try {
      request.logout();
      HttpSession session = request.getSession(false);
      if (session != null) {
        session.invalidate();
      }
      Cookie[] cookies = request.getCookies();
      if (cookies != null) {
        for (Cookie c : cookies) {
          if ("LtpaToken2".equals(c.getName()) || "LtpaToken".equals(c.getName()) || "JSESSIONID".equals(c.getName())) {
            Cookie expired = new Cookie(c.getName(), "");
            expired.setMaxAge(0);
            expired.setPath("/");
            response.addCookie(expired);
          }
        }
      }
    } catch (Exception e) {
      System.err.println("[ERROR] Error logging out");
      e.printStackTrace();
    }

    response.sendRedirect("login.jsp");
  }
}
