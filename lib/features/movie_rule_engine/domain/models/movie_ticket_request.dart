/// Request model for movie ticket optimization
class MovieTicketRequest {
  final int numberOfTickets;
  final double pricePerTicket;
  final String? preferredCinema; // Optional
  final String? preferredPlatform; // Optional

  const MovieTicketRequest({
    required this.numberOfTickets,
    required this.pricePerTicket,
    this.preferredCinema,
    this.preferredPlatform,
  });

  double get totalAmount => numberOfTickets * pricePerTicket;

  Map<String, dynamic> toJson() => {
    'numberOfTickets': numberOfTickets,
    'pricePerTicket': pricePerTicket,
    'preferredCinema': preferredCinema,
    'preferredPlatform': preferredPlatform,
    'totalAmount': totalAmount,
  };

  factory MovieTicketRequest.fromJson(Map<String, dynamic> json) {
    return MovieTicketRequest(
      numberOfTickets: json['numberOfTickets'] ?? 0,
      pricePerTicket: (json['pricePerTicket'] ?? 0.0).toDouble(),
      preferredCinema: json['preferredCinema'],
      preferredPlatform: json['preferredPlatform'],
    );
  }

  @override
  String toString() => 'MovieTicketRequest('
      'tickets: $numberOfTickets, '
      'price: ₹$pricePerTicket, '
      'total: ₹$totalAmount'
      ')';
}
