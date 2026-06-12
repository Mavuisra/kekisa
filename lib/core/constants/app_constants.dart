/// Constantes partagées (stockage, API) - app parents CisnetKids
library;

/// Clés de stockage local (Secure Storage, Hive)
abstract class StorageKeys {
  static const String accessToken = 'cisnetkids_access_token';
  static const String refreshToken = 'cisnetkids_refresh_token';
  static const String userData = 'cisnetkids_user_data';
  static const String userBox = 'cisnetkids_user';
  static const String syncQueueBox = 'cisnetkids_sync_queue';
  static const String cacheBox = 'cisnetkids_cache';
}

/// Timeouts et config API
abstract class ApiConstants {
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 15);
}

/// Endpoints API (relatifs à la base api/v1)
abstract class ApiEndpoints {
  static const String login = '/users/auth/login/';
  static const String register = '/users/auth/register/';
  static const String passwordResetRequest = '/users/auth/password-reset/request/';
  static const String passwordResetConfirm = '/users/auth/password-reset/confirm/';
  static const String changePassword = '/users/auth/change-password/';
  static const String pushDevices = '/users/push-devices/';
  static const String refresh = '/token/refresh/';
  static const String dashboard = '/users/dashboard/';
  static const String myTermResults = '/users/my-term-results/';
  static const String myGrades = '/users/my-grades/';
  static const String myAttendance = '/users/my-attendance/';
  static const String myInvoices = '/users/my-invoices/';
  static const String myLearningSuggestions = '/users/my-learning-suggestions/';
  static const String myNotifications = '/users/my-notifications/';
  static const String myConversations = '/users/my-conversations/';
  static String myConversationMessages(int id) =>
      '/users/my-conversations/$id/messages/';

  // Enseignant
  static const String teacherDashboard = '/users/teachers/dashboard/';
  static const String teacherMyClasses = '/users/teachers/my-classes/';
  static String teacherClassStudents(int classroomId) =>
      '/users/teachers/my-classes/$classroomId/students/';
  static const String teacherMyGrades = '/users/teachers/my-grades/';
  static const String teacherMyAttendance = '/users/teachers/my-attendance/';
  static const String teacherMyConversations =
      '/users/teachers/my-conversations/';
  static String teacherConversationMessages(int id) =>
      '/users/teachers/my-conversations/$id/messages/';
  static String teacherSendMessage(int id) =>
      '/users/teachers/my-conversations/$id/messages/send/';
  static const String teacherCreatePost = '/users/teachers/posts/';

  // Commerce
  static const String commerceProducts = '/commerce/products/';
  static const String commerceCustomers = '/commerce/customers/';
  static const String commerceStockOverview = '/commerce/stock/overview/';
  static const String commerceStockAdd = '/commerce/stock/add/';
  static const String commerceStockMovements = '/commerce/stock/movements/';
  static const String commerceSalesSummary = '/commerce/sales/summary/';
  static const String commerceSalesAiDraft = '/commerce/sales/ai-draft/';
  static const String commerceSalesList = '/commerce/sales/list/';
  static const String commerceSalesExport = '/commerce/sales/export.xlsx';
  static const String commerceStockExport = '/commerce/stock/export.xlsx';
  static String commerceSaleDetail(int saleId) => '/commerce/sales/$saleId/';
  static String commerceSaleCancel(int saleId) =>
      '/commerce/sales/$saleId/cancel/';
  static const String commerceReceiptVerify = '/commerce/sales/receipt-verify/';
  static const String commerceQuickSale = '/commerce/sales/quick/';
  static const String commerceCustomersSummary = '/commerce/customers/summary/';
  static const String commerceInsights = '/commerce/insights/';
  static const String commerceAccountingReports =
      '/commerce/accounting/reports/';
  static const String commerceSupplierMyProfile =
      '/commerce/suppliers/my-profile/';
  static const String commerceSupplierMyProducts =
      '/commerce/suppliers/my-products/';
  static const String commerceSupplierNearby = '/commerce/suppliers/nearby/';
  static const String commerceSupplierMarketplace =
      '/commerce/suppliers/marketplace/';
  static const String commerceSupplierKinshasaLocations =
      '/commerce/suppliers/kinshasa-locations/';
  static const String commerceSupplierOrders = '/commerce/suppliers/orders/';
  static String commerceSupplierOrderStatus(int orderId) =>
      '/commerce/suppliers/orders/$orderId/status/';
  static const String commerceSupplierCallStart =
      '/commerce/suppliers/calls/start/';
  static const String commerceSupplierCallEnd =
      '/commerce/suppliers/calls/end/';
  static const String commerceSupplierUploadImage =
      '/commerce/suppliers/upload-image/';
  static const String commerceSupplierUploadAudio =
      '/commerce/suppliers/upload-audio/';
  static const String commerceSupplierUploadFile =
      '/commerce/suppliers/upload-file/';
  static const String commerceSupplierConversations =
      '/commerce/suppliers/conversations/';
  static String commerceSupplierConversationMessages(int conversationId) =>
      '/commerce/suppliers/conversations/$conversationId/messages/';
  static const String commerceSupplierQuickOrder =
      '/commerce/suppliers/orders/quick/';
  static const String commerceSalonSales = '/commerce/salon/sales/';
  static const String commerceSalonServices = '/commerce/salon/services/';
  static const String commerceSalonStaff = '/commerce/salon/staff/';
  static const String commerceAdminOverview = '/commerce/admin/overview/';
  static const String commerceAdminSellersActivity =
      '/commerce/admin/sellers-activity/';
}
