package com.acme.modres.mbean.reservation;

import java.util.Date;

import com.acme.modres.Constants;

public class ReservationCheckerData {
  private ReservationList reservations;
  private java.time.LocalDate selectedDate; // date-only, maps to PostgreSQL DATE
  private boolean available; // changed from Boolean to boolean

  public ReservationCheckerData(ReservationList reservations) {
    this.reservations = reservations;
    this.available = true;
  }

  public ReservationList getReservationList() {
    return reservations;
  }

  public Date getSelectedDate() {
    return selectedDate == null ? null
        : Date.from(selectedDate.atStartOfDay(java.time.ZoneOffset.UTC).toInstant());
  }

  /** Date-only view (PostgreSQL DATE has no time component). */
  public java.time.LocalDate getSelectedLocalDate() {
    return selectedDate;
  }

  public boolean setSelectedDate(String dateStr) {
    try {
      selectedDate = Constants.utcDateFormat().parse(dateStr).toInstant()
          .atZone(java.time.ZoneOffset.UTC).toLocalDate();
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
