package com.acme.modres.mbean.reservation;

import java.text.SimpleDateFormat;
import java.util.Date;

import com.acme.modres.Constants;

public class ReservationCheckerData {
  private ReservationList reservations;
  // In-memory, date-only value (MM/dd/yyyy); not persisted. If stored in PostgreSQL, use a DATE column.
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
      selectedDate = new SimpleDateFormat(Constants.DATA_FORMAT).parse(dateStr);
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
