import localUnitTest from './LocalUnit.test';
import capsuleValidatorTest from './CapsuleValidator.test';

export default function testsuite() {
  localUnitTest();
  capsuleValidatorTest();
}
