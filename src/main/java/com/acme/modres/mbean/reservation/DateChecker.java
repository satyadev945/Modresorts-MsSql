package com.acme.modres.mbean.reservation;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.List;

import com.acme.modres.Constants;

public class DateChecker implements Runnable {
  private static final DateTimeFormatter formatter = DateTimeFormatter.ofPattern(Constants.DATA_FORMAT);
  ReservationCheckerData data;
  List<Reservation> reservations;

  public DateChecker(ReservationCheckerData data) {
    this.data = data;
    this.reservations = data.getReservationList().getReservations();
  }

  public void run() {
    for (int i = 0; i < reservations.size(); i++) {
      Reservation reservation = reservations.get(i);
      Instant selectedDate = data.getSelectedDate();

      try {
        Instant fromDate = LocalDate.parse(reservation.getFromDate(), formatter).atStartOfDay(ZoneOffset.UTC).toInstant();
        Instant toDate = LocalDate.parse(reservation.getToDate(), formatter).atStartOfDay(ZoneOffset.UTC).toInstant();
        if (selectedDate.isAfter(fromDate) && selectedDate.isBefore(toDate)) {
          data.setAvailablility(false);
          break;
        }
      } catch (DateTimeParseException ex) {
        ex.printStackTrace();
      }
    }
    data.setAvailablility(true);
  }
}
