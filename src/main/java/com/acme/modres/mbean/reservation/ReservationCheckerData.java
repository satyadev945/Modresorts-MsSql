package com.acme.modres.mbean.reservation;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;

import com.acme.modres.Constants;

public class ReservationCheckerData {
  private ReservationList reservations;
  private Instant selectedDate;
  private boolean available; // changed from Boolean to boolean

  public ReservationCheckerData(ReservationList reservations) {
    this.reservations = reservations;
    this.available = true;
  }

  /**
   * Parses a date string using Constants.DATA_FORMAT and returns the start of that day in UTC.
   */
  public static Instant parseDate(String dateStr) {
    return LocalDate.parse(dateStr, DateTimeFormatter.ofPattern(Constants.DATA_FORMAT))
        .atStartOfDay(ZoneOffset.UTC).toInstant();
  }

  public ReservationList getReservationList() {
    return reservations;
  }

  public Instant getSelectedDate() {
    return selectedDate;
  }

  public boolean setSelectedDate(String dateStr) {
    try {
      selectedDate = parseDate(dateStr);
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
