import localUnitTest from './LocalUnit.test';
import capsuleValidatorTest from './CapsuleValidator.test';
import ruleParserTest from './RuleParser.test';
import capsuleModelTest from './CapsuleModel.test';
import capsuleGeneratorTest from './CapsuleGenerator.test';
import capsuleRouterTest from './CapsuleRouter.test';
import widgetModelTest from './WidgetModel.test';
import exprTest from './Expr.test';
import capsuleV1Test from './CapsuleV1.test';
import sharedTextTest from './SharedText.test';
import triggersTest from './Triggers.test';
import sharingTest from './Sharing.test';
import createTextTest from './CreateText.test';

export default function testsuite() {
  localUnitTest();
  capsuleValidatorTest();
  ruleParserTest();
  capsuleModelTest();
  capsuleGeneratorTest();
  capsuleRouterTest();
  widgetModelTest();
  exprTest();
  capsuleV1Test();
  sharedTextTest();
  triggersTest();
  sharingTest();
  createTextTest();
}
