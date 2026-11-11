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

  private static final DateTimeFormatter DATE_FORMATTER = DateTimeFormatter.ofPattern(Constants.DATA_FORMAT)
      .withZone(ZoneOffset.UTC);

  /**
   * Parses a date string (Constants.DATA_FORMAT) as the start of day in UTC.
   *
   * @throws java.time.format.DateTimeParseException if the value cannot be parsed
   */
  public static Instant parseDate(String dateStr) {
    return LocalDate.parse(dateStr, DATE_FORMATTER).atStartOfDay(ZoneOffset.UTC).toInstant();
  }

  public ReservationCheckerData(ReservationList reservations) {
    this.reservations = reservations;
    this.available = true;
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
