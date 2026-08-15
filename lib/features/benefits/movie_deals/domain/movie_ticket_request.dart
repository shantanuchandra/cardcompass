// lib/features/benefits/movie_deals/domain/movie_ticket_request.dart

/// One search: how many tickets, at what price, on which platform/cinema.
/// Cinema is accepted and carried through but never filters or affects
/// confidence — design spec §1.1/§7 step 2: no real row carries cinema-chain
/// data, so every rule is currently cinema-agnostic. This is a stated,
/// deliberate gap, not an oversight.
class MovieTicketRequest {
  const MovieTicketRequest({
    required this.numberOfTickets,
    required this.pricePerTicket,
    this.preferredPlatform,
    this.preferredCinema,
  });

  final int numberOfTickets;
  final double pricePerTicket;
  final String? preferredPlatform;
  final String? preferredCinema;

  double get totalAmount => numberOfTickets * pricePerTicket;
}
