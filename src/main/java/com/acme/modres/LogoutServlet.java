package com.acme.modres;

import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import java.io.IOException;

@WebServlet({ "/logout" })
public class LogoutServlet extends HttpServlet {
  private static final long serialVersionUID = 1L;

  @Override
  protected void doGet(HttpServletRequest request,
      HttpServletResponse response) throws IOException {

    try {
      request.logout();
      if (request.getSession(false) != null) {
        request.getSession(false).invalidate();
      }
      javax.servlet.http.Cookie ssoCookie = new javax.servlet.http.Cookie("LtpaToken2", "");
      ssoCookie.setMaxAge(0);
      ssoCookie.setPath("/");
      response.addCookie(ssoCookie);
    } catch (Exception e) {
      System.err.println("[ERROR] Error logging out");
      e.printStackTrace();
    }

    response.sendRedirect("login.jsp");
  }
}
