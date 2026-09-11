# ==============================================================================
# Candidate Name: Pranav Dogra
# Email: pranavdograa@gmail.com
# Module: Local Execution Test for DRF Serializer
# ==============================================================================
import os
import django
from django.conf import settings

if not settings.configured:
    settings.configure(
        SECRET_KEY="test-secret-key",
        INSTALLED_APPS=["rest_framework"],
    )
    django.setup()

from serializers import StudentOnboardingSerializer

valid_payload = {
    "student_id": "STU-99412",
    "first_name": "John",
    "last_name": "Doe",
    "age": 10,
    "has_learning_disability": True,
    "guardian_email": "parent@gmail.com",
    "requires_lsa_support": True,
}

serializer = StudentOnboardingSerializer(data=valid_payload)
if serializer.is_valid():
    print("SUCCESS: Payload Validation Passed.")
    print(
        "DCYN Transformed Output:",
        serializer.to_representation(serializer.validated_data),
    )
else:
    print("FAILURE:", serializer.errors)
