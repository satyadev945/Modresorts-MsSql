package com.acme.modres.mbean.reservation;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;

import com.acme.modres.Constants;

public class ReservationCheckerData {
  private ReservationList reservations;
  private LocalDate selectedLocalDate; // date-only, matches PostgreSQL DATE
  private boolean available; // changed from Boolean to boolean

  private static final DateTimeFormatter DATE_FORMATTER = DateTimeFormatter.ofPattern(Constants.DATA_FORMAT)
      .withZone(ZoneOffset.UTC);

  /**
   * Parses a date string (Constants.DATA_FORMAT) as the start of day in UTC.
   *
   * @throws java.time.format.DateTimeParseException if the value cannot be parsed
   */
  public static Instant parseDate(String dateStr) {
    return parseLocalDate(dateStr).atStartOfDay(ZoneOffset.UTC).toInstant();
  }

  /**
   * Parses a date-only string into a java.time.LocalDate. This is the type to use
   * for PostgreSQL DATE columns (no time component); with JDBC use
   * setObject/getObject(..., LocalDate.class).
   */
  public static LocalDate parseLocalDate(String dateStr) {
    return LocalDate.parse(dateStr, DATE_FORMATTER);
  }

  public ReservationCheckerData(ReservationList reservations) {
    this.reservations = reservations;
    this.available = true;
  }

  public ReservationList getReservationList() {
    return reservations;
  }

  public Instant getSelectedDate() {
    return selectedLocalDate == null ? null : selectedLocalDate.atStartOfDay(ZoneOffset.UTC).toInstant();
  }

  /** Date-only view of the selected date (maps to PostgreSQL DATE). */
  public LocalDate getSelectedLocalDate() {
    return selectedLocalDate;
  }

  public boolean setSelectedDate(String dateStr) {
    try {
      selectedLocalDate = parseLocalDate(dateStr);
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
