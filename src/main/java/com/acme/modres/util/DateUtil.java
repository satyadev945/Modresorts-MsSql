package com.acme.modres.util;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.TimeZone;

import com.acme.modres.Constants;

/**
 * Timezone-agnostic date parsing. Dates are always interpreted in UTC (configurable through the
 * APP_TIMEZONE environment variable) so behaviour does not depend on the server-local timezone of
 * the container / region the application runs in.
 */
public final class DateUtil {

  private DateUtil() {
  }

  public static TimeZone getTimeZone() {
    String tz = System.getenv("APP_TIMEZONE");
    if (tz == null || tz.trim().isEmpty()) {
      tz = "UTC";
    }
    return TimeZone.getTimeZone(tz.trim());
  }

  /** Parses a reservation date (Constants.DATA_FORMAT) using a fixed timezone. */
  public static Date parse(String dateStr) throws ParseException {
    // SimpleDateFormat is not thread-safe: create a new instance per call
    SimpleDateFormat format = new SimpleDateFormat(Constants.DATA_FORMAT);
    format.setTimeZone(getTimeZone());
    return format.parse(dateStr);
  }
}
