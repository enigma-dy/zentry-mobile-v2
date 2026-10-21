class ContactRequest {
  final String name;
  final String email;
  final String subject;
  final String message;

  ContactRequest({
    required this.name,
    required this.email,
    required this.subject,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'subject': subject,
        'message': message,
      };
}

class ContactResponse {
  final bool success;
  final String message;
  final String ticketId;
  final String? createdAt;

  ContactResponse({
    required this.success,
    required this.message,
    required this.ticketId,
    this.createdAt,
  });

  factory ContactResponse.fromJson(Map<String, dynamic> json) {
    return ContactResponse(
      success: json['success'] as bool? ?? true,
      message: json['message'] as String? ?? 'Message submitted successfully',
      ticketId: json['ticket_id'] as String? ?? json['ticketId'] as String? ?? 'ST-00000',
      createdAt: json['created_at'] as String?,
    );
  }
}

class FAQItem {
  final int id;
  final String category;
  final String question;
  final String answer;

  FAQItem({
    required this.id,
    required this.category,
    required this.question,
    required this.answer,
  });

  factory FAQItem.fromJson(Map<String, dynamic> json) {
    return FAQItem(
      id: json['id'] as int? ?? 0,
      category: json['category'] as String? ?? 'General',
      question: json['question'] as String? ?? '',
      answer: json['answer'] as String? ?? '',
    );
  }
}

class ContactInfo {
  final String email;
  final String phone;
  final String whatsapp;
  final String hours;

  ContactInfo({
    required this.email,
    required this.phone,
    required this.whatsapp,
    required this.hours,
  });

  factory ContactInfo.fromJson(Map<String, dynamic> json) {
    return ContactInfo(
      email: json['email'] as String? ?? 'support@zentrypredict.com',
      phone: json['phone'] as String? ?? '+234 800 ZENTRY',
      whatsapp: json['whatsapp'] as String? ?? '+234 812 345 6789',
      hours: json['hours'] as String? ?? '24/7 Support Available',
    );
  }
}

class HelpInfo {
  final ContactInfo contactInfo;
  final List<FAQItem> faqs;

  HelpInfo({
    required this.contactInfo,
    required this.faqs,
  });

  factory HelpInfo.fromJson(Map<String, dynamic> json) {
    final infoMap = json['contact_info'] as Map<String, dynamic>? ?? {};
    final faqList = json['faqs'] as List<dynamic>? ?? [];

    return HelpInfo(
      contactInfo: ContactInfo.fromJson(infoMap),
      faqs: faqList
          .whereType<Map<String, dynamic>>()
          .map((m) => FAQItem.fromJson(m))
          .toList(),
    );
  }
}
