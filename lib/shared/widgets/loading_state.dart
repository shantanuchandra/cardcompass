import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/core/theme.dart';

class LoadingState extends StatelessWidget {
  final String? message;
  final double? size;

  const LoadingState({
    super.key,
    this.message,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: size ?? 32,
            height: size ?? 32,
            child: const CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppTheme.primaryColor,
              ),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class LoadingSpinner extends StatelessWidget {
  final String? message;
  final double? size;
  final Color? color;

  const LoadingSpinner({
    super.key,
    this.message,
    this.size,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size ?? 24,
          height: size ?? 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              color ?? AppTheme.primaryColor,
            ),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          Text(
            message!.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white38,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback? onRetry;
  final String? retryText;
  final IconData? icon;

  const ErrorState({
    super.key,
    required this.error,
    this.onRetry,
    this.retryText,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0C152B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.25), width: 1.2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon ?? Icons.warning_amber_outlined,
                size: 48,
                color: AppTheme.errorColor,
              ),
              const SizedBox(height: 16),
              Text(
                'SYSTEM DISCREPANCY',
                style: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1.0,
                  color: AppTheme.errorColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                error,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white70,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 14, color: AppTheme.errorColor),
                  label: Text(
                    (retryText ?? 'RETRY CONNECTION').toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTheme.errorColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.errorColor, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String title;
  final String message;
  final IconData? icon;
  final String? buttonText;
  final VoidCallback? onButtonPressed;
  final Widget? illustration;

  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.buttonText,
    this.onButtonPressed,
    this.illustration,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0C152B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (illustration != null)
                illustration!
              else
                Icon(
                  icon ?? Icons.inbox_outlined,
                  size: 40,
                  color: Colors.white38,
                ),
              const SizedBox(height: 16),
              Text(
                title.toUpperCase(),
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                message,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white60,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
              if (buttonText != null && onButtonPressed != null) ...[
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: onButtonPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: Text(
                    buttonText!.toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class NetworkErrorState extends StatelessWidget {
  final VoidCallback? onRetry;
  final String? message;

  const NetworkErrorState({
    super.key,
    this.onRetry,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return ErrorState(
      error: message ?? 'No internet connection. Please check your network and try again.',
      icon: Icons.wifi_off,
      onRetry: onRetry,
      retryText: 'Try Again',
    );
  }
}

class NotFoundState extends StatelessWidget {
  final String? title;
  final String? message;
  final VoidCallback? onGoBack;

  const NotFoundState({
    super.key,
    this.title,
    this.message,
    this.onGoBack,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: title ?? 'Not Found',
      message: message ?? 'The requested resource could not be found.',
      icon: Icons.search_off,
      buttonText: 'Go Back',
      onButtonPressed: onGoBack ?? () => Navigator.of(context).pop(),
    );
  }
}

class NoDataState extends StatelessWidget {
  final String? title;
  final String? message;
  final String? actionText;
  final VoidCallback? onAction;

  const NoDataState({
    super.key,
    this.title,
    this.message,
    this.actionText,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: title ?? 'No Data',
      message: message ?? 'No data available to display.',
      icon: Icons.data_usage_outlined,
      buttonText: actionText,
      onButtonPressed: onAction,
    );
  }
}
