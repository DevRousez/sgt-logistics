import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'dart:convert';
import '../api/api_service.dart';
import '../endpoints/api_endpoints.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static String? timezoneName;
  static String? lastScheduledInfo;
  static int? configuredWeekday;
  static int? configuredHour;
  static int? configuredMinute;

  static bool isTodayNotificationDay() {
    final int todayWeekday = tz.TZDateTime.now(tz.local).weekday;
    final int targetWeekday = configuredWeekday ?? DateTime.saturday;
    return todayWeekday == targetWeekday;
  }

  static String getWeekdayName(int? weekday) {
    switch (weekday) {
      case 1:
        return "Lunes";
      case 2:
        return "Martes";
      case 3:
        return "Miércoles";
      case 4:
        return "Jueves";
      case 5:
        return "Viernes";
      case 6:
        return "Sábado";
      case 7:
        return "Domingo";
      default:
        return "Sábado";
    }
  }

  static Future<void> init() async {
    tz.initializeTimeZones();
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      final String timeZoneName = timezoneInfo.identifier;
      timezoneName = timeZoneName;
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      print("NotificationService: Zona horaria inicializada: $timeZoneName");
    } catch (e) {
      print("NotificationService: Error al inicializar la zona horaria: $e");
    }
    
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Manejar click en notificación si se requiere en el futuro
      },
    );

    // Crear canal explícito de Android
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          'weekly_notification_channel',
          'Captura de Gastos',
          description: 'Recordatorio semanal para capturar los gastos de viaje',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
    }
  }

  static Future<void> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      final bool? granted = await androidImplementation.requestNotificationsPermission();
      print("NotificationService: Permiso POST_NOTIFICATIONS: $granted");
      try {
        final bool? exactGranted = await androidImplementation.requestExactAlarmsPermission();
        print("NotificationService: Permiso EXACT_ALARMS: $exactGranted");
      } catch (e) {
        print("NotificationService: requestExactAlarmsPermission error/no soportado: $e");
      }
    }
  }

  static Future<void> fetchAndScheduleNotification() async {
    try {
      final response = await ApiService.get(ApiEndpoints.notificationConfig);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['value'] != null) {
          final String val = data['value'].toString().trim(); // Espera "weekday HH:MM", ej: "6 10:00"
          final parts = val.split(' ');
          if (parts.length == 2) {
            final int? weekday = int.tryParse(parts[0]);
            final timeParts = parts[1].split(':');
            if (weekday != null && timeParts.length >= 2) {
              final int? hour = int.tryParse(timeParts[0]);
              final int? minute = int.tryParse(timeParts[1]);
              if (hour != null && minute != null) {
                configuredWeekday = weekday;
                configuredHour = hour;
                configuredMinute = minute;
                await scheduleWeeklyNotification(weekday, hour, minute);
                print("NotificationService: Notificación programada para día $weekday a las $hour:$minute");
                return;
              }
            }
          }
        }
      }
      // Valor por defecto: Sábado (6) a las 10:00 AM
      configuredWeekday = DateTime.saturday;
      configuredHour = 10;
      configuredMinute = 0;
      await scheduleWeeklyNotification(DateTime.saturday, 10, 0);
      print("NotificationService: Programada por defecto: Sábado 10:00 AM");
    } catch (e) {
      print("NotificationService: Error al obtener o programar: $e");
      try {
        configuredWeekday = DateTime.saturday;
        configuredHour = 10;
        configuredMinute = 0;
        await scheduleWeeklyNotification(DateTime.saturday, 10, 0);
      } catch (ex) {
        print("NotificationService: Error en el fallback: $ex");
      }
    }
  }

  static Future<void> scheduleWeeklyNotification(int weekday, int hour, int minute) async {
    // Cancelar notificaciones previas con el mismo ID para evitar duplicados
    await _notificationsPlugin.cancel(id: 1001);

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = _nextInstanceOfWeekdayAndTime(now, weekday, hour, minute);

    print("NotificationService: Hora actual: $now");
    print("NotificationService: Programando fecha de notificación: $scheduledDate (weekday: ${scheduledDate.weekday})");

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'weekly_notification_channel',
      'Captura de Gastos',
      channelDescription: 'Recordatorio semanal para capturar los gastos de viaje',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    try {
      await _notificationsPlugin.zonedSchedule(
        id: 1001,
        title: 'Sita App',
        body: 'se requiere que capture los gastos de los viajes de la semana, ya que esta proximo a su liquidacion.',
        scheduledDate: scheduledDate,
        notificationDetails: platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
      lastScheduledInfo = "Programada EXACTA para: $scheduledDate (Día semana: $weekday, Hora: $hour:${minute.toString().padLeft(2, '0')})";
      print("NotificationService: Programada exitosamente como EXACTA.");
    } catch (e) {
      print("NotificationService: Alarma exacta falló ($e), reintentando como inexacta...");
      await _notificationsPlugin.zonedSchedule(
        id: 1001,
        title: 'Sita App',
        body: 'se requiere que capture los gastos de los viajes de la semana, ya que esta proximo a su liquidacion.',
        scheduledDate: scheduledDate,
        notificationDetails: platformDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
      lastScheduledInfo = "Programada INEXACTA para: $scheduledDate (Día semana: $weekday, Hora: $hour:${minute.toString().padLeft(2, '0')})";
      print("NotificationService: Programada exitosamente como INEXACTA.");
    }
  }

  static Future<void> showInstantTestNotification() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'weekly_notification_channel',
      'Captura de Gastos',
      channelDescription: 'Recordatorio semanal para capturar los gastos de viaje',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      id: 9999,
      title: 'Sita App - Prueba Inmediata',
      body: '¡Esta es una notificación de prueba instantánea!',
      notificationDetails: platformDetails,
    );
  }

  static Future<tz.TZDateTime> scheduleTestNotificationInSeconds(int seconds) async {
    final tz.TZDateTime scheduledDate =
        tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'weekly_notification_channel',
      'Captura de Gastos',
      channelDescription: 'Recordatorio semanal para capturar los gastos de viaje',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    try {
      await _notificationsPlugin.zonedSchedule(
        id: 9998,
        title: 'Sita App - Prueba ($seconds seg)',
        body: 'La notificación programada se ejecutó con éxito.',
        scheduledDate: scheduledDate,
        notificationDetails: platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      await _notificationsPlugin.zonedSchedule(
        id: 9998,
        title: 'Sita App - Prueba ($seconds seg)',
        body: 'La notificación programada se ejecutó con éxito.',
        scheduledDate: scheduledDate,
        notificationDetails: platformDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }

    return scheduledDate;
  }

  static tz.TZDateTime _nextInstanceOfWeekdayAndTime(
      tz.TZDateTime now, int weekday, int hour, int minute) {
    tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, hour, minute);
    
    while (scheduledDate.weekday != weekday || scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}
