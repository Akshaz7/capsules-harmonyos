import localUnitTest from './LocalUnit.test';
import capsuleValidatorTest from './CapsuleValidator.test';
import ruleParserTest from './RuleParser.test';
import capsuleModelTest from './CapsuleModel.test';
import capsuleGeneratorTest from './CapsuleGenerator.test';
import capsuleRouterTest from './CapsuleRouter.test';
import widgetModelTest from './WidgetModel.test';
import sharingTest from './Sharing.test';

export default function testsuite() {
  localUnitTest();
  capsuleValidatorTest();
  ruleParserTest();
  capsuleModelTest();
  capsuleGeneratorTest();
  capsuleRouterTest();
  widgetModelTest();
  sharingTest();
}
