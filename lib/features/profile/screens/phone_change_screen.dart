import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';

/// 전화번호 변경 화면
/// 새 번호 입력 → OTP 발송 → OTP 확인 → 변경 적용
class PhoneChangeScreen extends ConsumerStatefulWidget {
  const PhoneChangeScreen({super.key, required this.currentPhone});

  final String currentPhone;

  @override
  ConsumerState<PhoneChangeScreen> createState() =>
      _PhoneChangeScreenState();
}

class _PhoneChangeScreenState extends ConsumerState<PhoneChangeScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  String? _verificationId;
  bool _sending = false;
  bool _verifying = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;
    if (AuthService.instance.cleanPhone(phone) ==
        AuthService.instance.cleanPhone(widget.currentPhone)) {
      _snack('현재 사용 중인 번호와 같아요.');
      return;
    }

    setState(() => _sending = true);
    await AuthService.instance.sendPhoneChangeOtp(
      newPhone: phone,
      onCodeSent: (vid) {
        if (!mounted) return;
        setState(() {
          _verificationId = vid;
          _sending = false;
        });
        _snack('인증번호를 보냈어요.');
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() => _sending = false);
        _snack(msg);
      },
    );
  }

  Future<void> _confirm() async {
    final vid = _verificationId;
    if (vid == null) return;
    final otp = _otpController.text.trim();
    if (otp.length < 6) return;

    setState(() => _verifying = true);
    final ok = await AuthService.instance.confirmPhoneChange(
      newPhone: _phoneController.text.trim(),
      verificationId: vid,
      smsCode: otp,
      onError: (msg) {
        if (!mounted) return;
        setState(() => _verifying = false);
        _snack(msg);
      },
    );
    if (!mounted) return;
    if (ok) {
      _snack('전화번호를 변경했어요.');
      Navigator.of(context).pop(true);
    } else {
      setState(() => _verifying = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final hasVid = _verificationId != null;

    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      appBar: AppBar(title: const Text('전화번호 변경')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('현재 번호',
                  style:
                      AppTheme.body(size: 12, color: AppTheme.textLight)),
              const SizedBox(height: 4),
              Text(_formatPhone(widget.currentPhone),
                  style: AppTheme.body(
                      size: 16, weight: FontWeight.w600)),
              const SizedBox(height: 24),

              Text('새 번호',
                  style:
                      AppTheme.body(size: 12, color: AppTheme.textLight)),
              const SizedBox(height: 6),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                enabled: !hasVid,
                style: AppTheme.body(size: 16, weight: FontWeight.w600),
                decoration: const InputDecoration(
                  hintText: '01012345678',
                ),
              ),
              const SizedBox(height: 12),

              if (!hasVid)
                ElevatedButton(
                  onPressed: _sending ? null : _sendOtp,
                  child: _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppTheme.textOnPrimary),
                        )
                      : const Text('인증번호 받기'),
                ),

              if (hasVid) ...[
                const SizedBox(height: 20),
                Text('인증번호',
                    style: AppTheme.body(
                        size: 12, color: AppTheme.textLight)),
                const SizedBox(height: 6),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  style: AppTheme.body(size: 18, weight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: '6자리 숫자',
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _verifying ? null : _confirm,
                  child: _verifying
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppTheme.textOnPrimary),
                        )
                      : const Text('변경하기'),
                ),
              ],

              const Spacer(),
              Text(
                '새 번호로 인증번호가 발송돼요. 인증을 마치면 다음부터 새 번호로 로그인할 수 있어요.',
                textAlign: TextAlign.center,
                style: AppTheme.body(
                    size: 12, color: AppTheme.textLight, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPhone(String phone) {
    if (phone.length != 11) return phone;
    return '${phone.substring(0, 3)}-${phone.substring(3, 7)}-${phone.substring(7)}';
  }
}