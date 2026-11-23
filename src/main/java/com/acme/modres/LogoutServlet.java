package com.acme.modres;

import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import javax.servlet.http.Cookie;
import javax.servlet.http.HttpSession;

import java.io.IOException;

@WebServlet({ "/logout" })
public class LogoutServlet extends HttpServlet {
  private static final long serialVersionUID = 1L;

  @Override
  protected void doGet(HttpServletRequest request,
      HttpServletResponse response) throws IOException {

    try {
      HttpSession session = request.getSession(false);
      if (session != null) {
        session.invalidate();
      }
      Cookie[] cookies = request.getCookies();
      if (cookies != null) {
        for (Cookie cookie : cookies) {
          if ("LtpaToken2".equals(cookie.getName()) || "LtpaToken".equals(cookie.getName())
              || "JSESSIONID".equals(cookie.getName())) {
            cookie.setValue("");
            cookie.setMaxAge(0);
            cookie.setPath("/");
            response.addCookie(cookie);
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
