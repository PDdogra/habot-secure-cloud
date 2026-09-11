# ==============================================================================
# Candidate Name: Pranav Dogra
# Email: pranavdograa@gmail.com
# Module: Local Execution & Automated Test Suite for DRF Serializer
# ==============================================================================
import os
import sys
import unittest
import django
from django.conf import settings

# Configure minimal headless Django environment for DRF testing
if not settings.configured:
    settings.configure(
        SECRET_KEY="test-secret-key",
        INSTALLED_APPS=["rest_framework"],
    )
    django.setup()

from serializers import StudentOnboardingSerializer

# Baseline valid payload used for interactive verification & proof collection
valid_payload = {
    "student_id": "STU-99412",
    "first_name": "John",
    "last_name": "Doe",
    "age": 10,
    "has_learning_disability": True,
    "guardian_email": "parent@gmail.com",
    "requires_lsa_support": True,
}


class TestStudentOnboardingSerializer(unittest.TestCase):
    """
    Automated test suite verifying field constraints, domain whitelisting,
    and Discrete Condition Yes/No (DCYN) binary transformations.
    """

    def test_valid_payload_dcyn_positive(self):
        """Test valid payload with positive flags generates DCYN 1 values."""
        serializer = StudentOnboardingSerializer(data=valid_payload)
        self.assertTrue(serializer.is_valid(), serializer.errors)
        output = serializer.to_representation(serializer.validated_data)
        self.assertEqual(output["has_learning_disability_dcyn"], 1)
        self.assertEqual(output["requires_lsa_support_dcyn"], 1)

    def test_valid_payload_dcyn_negative(self):
        """Test valid payload with false flags generates DCYN 0 values."""
        payload = dict(valid_payload)
        payload["has_learning_disability"] = False
        payload["requires_lsa_support"] = False
        serializer = StudentOnboardingSerializer(data=payload)
        self.assertTrue(serializer.is_valid(), serializer.errors)
        output = serializer.to_representation(serializer.validated_data)
        self.assertEqual(output["has_learning_disability_dcyn"], 0)
        self.assertEqual(output["requires_lsa_support_dcyn"], 0)

    def test_age_boundary_enforcement(self):
        """Test age boundaries (min 3, max 21) reject out-of-range values."""
        underage = dict(valid_payload, age=2)
        serializer = StudentOnboardingSerializer(data=underage)
        self.assertFalse(serializer.is_valid())
        self.assertIn("age", serializer.errors)

        overage = dict(valid_payload, age=22)
        serializer = StudentOnboardingSerializer(data=overage)
        self.assertFalse(serializer.is_valid())
        self.assertIn("age", serializer.errors)

    def test_email_domain_whitelisting(self):
        """Test guardian email rejects non-whitelisted domains."""
        invalid_email = dict(
            valid_payload, guardian_email="parent@unauthorized-domain.com"
        )
        serializer = StudentOnboardingSerializer(data=invalid_email)
        self.assertFalse(serializer.is_valid())
        self.assertIn("guardian_email", serializer.errors)

    def test_missing_required_fields(self):
        """Test fail-closed behavior when critical fields are omitted."""
        incomplete = {"student_id": "STU-001"}
        serializer = StudentOnboardingSerializer(data=incomplete)
        self.assertFalse(serializer.is_valid())
        self.assertIn("first_name", serializer.errors)
        self.assertIn("guardian_email", serializer.errors)


if __name__ == "__main__":
    # 1. Primary proof verification output required by assessment
    serializer = StudentOnboardingSerializer(data=valid_payload)
    if serializer.is_valid():
        print("SUCCESS: Payload Validation Passed.")
        print(
            "DCYN Transformed Output:",
            serializer.to_representation(serializer.validated_data),
        )
    else:
        print("FAILURE:", serializer.errors)

    # 2. Automated test suite execution
    print("\nRunning Automated Test Suite...")
    suite = unittest.TestLoader().loadTestsFromTestCase(TestStudentOnboardingSerializer)
    runner = unittest.TextTestRunner(stream=sys.stdout, verbosity=2)
    result = runner.run(suite)
    if not result.wasSuccessful():
        exit(1)
