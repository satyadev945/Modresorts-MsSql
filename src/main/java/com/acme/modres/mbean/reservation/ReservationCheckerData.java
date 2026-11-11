package com.acme.modres.mbean.reservation;


import java.util.Date;

import com.acme.modres.util.DateUtil;

public class ReservationCheckerData {
  private ReservationList reservations;
  // Date-only value (maps to PostgreSQL DATE if persisted); not bound to any DB column here.
  // Callers (DateChecker, AvailabilityCheckerServlet) use java.util.Date, so type is retained.
  private Date selectedDate;
  private boolean available; // changed from Boolean to boolean

  public ReservationCheckerData(ReservationList reservations) {
    this.reservations = reservations;
    this.available = true;
  }

  public ReservationList getReservationList() {
    return reservations;
  }

  public Date getSelectedDate() {
    return selectedDate;
  }

  public boolean setSelectedDate(String dateStr) {
    try {
      selectedDate = DateUtil.parse(dateStr);
    } catch (Exception e) {
      return false;
    }
    return true;
  }

  public boolean isAvailible() {
    return available;
  }

  public void setAvailablility(boolean available) { // fix parameter type
    this.available = available;
  }
}
