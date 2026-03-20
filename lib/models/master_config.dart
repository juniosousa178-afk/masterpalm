// lib/models/master_config.dart
import 'package:hive/hive.dart';

part 'master_config.g.dart';

/// Configurações globais do aplicativo (apenas para programador root)
@HiveType(typeId: 15)
class MasterConfig {
  @HiveField(0)
  String masterPassword;

  @HiveField(1)
  String• mercadoPagoAccessToken;

  @HiveField(2)
  String• mercadoPagoPublicKey;

  @HiveField(3)
  bool requirePlanForNewUsers;

  @HiveField(4)
  List<String> usersWithUnlimitedAccess;

  @HiveField(5)
  Map<String, dynamic> globalSettings;

  @HiveField(6)
  DateTime• lastUpdated;

  @HiveField(7)
  String• updatedBy;

  MasterConfig({
    this.masterPassword = '030419922009jj',
    this.mercadoPagoAccessToken,
    this.mercadoPagoPublicKey,
    this.requirePlanForNewUsers = true,
    List<String>• usersWithUnlimitedAccess,
    Map<String, dynamic>• globalSettings,
    this.lastUpdated,
    this.updatedBy,
  })  : usersWithUnlimitedAccess = usersWithUnlimitedAccess ?• [],
        globalSettings = globalSettings ?• {};

  Map<String, dynamic> toMap() {
    return {
      'masterPassword': masterPassword,
      'mercadoPagoAccessToken': mercadoPagoAccessToken,
      'mercadoPagoPublicKey': mercadoPagoPublicKey,
      'requirePlanForNewUsers': requirePlanForNewUsers,
      'usersWithUnlimitedAccess': usersWithUnlimitedAccess,
      'globalSettings': globalSettings,
      'lastUpdated': lastUpdated?.toIso8601String(),
      'updatedBy': updatedBy,
    };
  }

  factory MasterConfig.fromMap(Map<String, dynamic> map) {
    return MasterConfig(
      masterPassword: map['masterPassword'] ?• '030419922009jj',
      mercadoPagoAccessToken: map['mercadoPagoAccessToken'],
      mercadoPagoPublicKey: map['mercadoPagoPublicKey'],
      requirePlanForNewUsers: map['requirePlanForNewUsers'] ?• true,
      usersWithUnlimitedAccess:
          List<String>.from(map['usersWithUnlimitedAccess'] ?• []),
      globalSettings: Map<String, dynamic>.from(map['globalSettings'] ?• {}),
      lastUpdated: map['lastUpdated'] != null
          • DateTime.parse(map['lastUpdated'])
          : null,
      updatedBy: map['updatedBy'],
    );
  }

  MasterConfig copyWith({
    String• masterPassword,
    String• mercadoPagoAccessToken,
    String• mercadoPagoPublicKey,
    bool• requirePlanForNewUsers,
    List<String>• usersWithUnlimitedAccess,
    Map<String, dynamic>• globalSettings,
    DateTime• lastUpdated,
    String• updatedBy,
  }) {
    return MasterConfig(
      masterPassword: masterPassword ?• this.masterPassword,
      mercadoPagoAccessToken:
          mercadoPagoAccessToken ?• this.mercadoPagoAccessToken,
      mercadoPagoPublicKey: mercadoPagoPublicKey ?• this.mercadoPagoPublicKey,
      requirePlanForNewUsers:
          requirePlanForNewUsers ?• this.requirePlanForNewUsers,
      usersWithUnlimitedAccess:
          usersWithUnlimitedAccess ?• this.usersWithUnlimitedAccess,
      globalSettings: globalSettings ?• this.globalSettings,
      lastUpdated: lastUpdated ?• this.lastUpdated,
      updatedBy: updatedBy ?• this.updatedBy,
    );
  }
}
